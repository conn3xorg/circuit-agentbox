# Facts give each host's distribution, which picks the package names and
# NodeSource's repository format.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = try(each.value.os, self.os_id) == self.os_id
      error_message = "Host ${each.key} is ${self.os_id}, not the ${try(each.value.os, "")} its os says."
    }
  }
}

locals {
  # A host object's os stands in for the facts of a host created in the
  # same plan, which can't be read until it exists.
  os     = { for name, h in var.hosts : name => try(h.os, data.conn3x_host.facts[name].os_id) }
  family = { for name, o in local.os : name => contains(["debian", "ubuntu"], o) ? "debian" : "redhat" }

  # Rocky Linux and AlmaLinux ship epel-release in their own extras
  # repository, and ripgrep is only in EPEL there. RHEL doesn't ship
  # epel-release, so EPEL has to be on there already.
  epel_hosts = { for name, h in var.hosts : name => h if contains(["rocky", "almalinux"], local.os[name]) }

  user = var.user
  home = "/home/${var.user}"

  # Commands that touch the user's own files run as the user, from their
  # home, so everything they create belongs to them.
  as_user = "cd ${local.home} && runuser -u ${local.user} --"

  workspace = var.workspace == null ? local.home : startswith(var.workspace, "/") ? var.workspace : "${local.home}/${var.workspace}"

  keys = { for k in var.ssh_keys : substr(sha256(trimspace(k)), 0, 12) => trimspace(k) }

  # Single quotes keep the shell from reading anything in these values.
  git_config = { for k, v in { "user.name" = var.git_name, "user.email" = var.git_email } : k => "'${replace(v, "'", "'\\''")}'" if v != null }

  repos = { for url in var.repos : trimsuffix(basename(url), ".git") => url }

  # Priority 9, as NodeSource's own setup script sets it, keeps dnf from
  # taking nodejs from the distribution's repositories instead.
  rpm_repo = <<-EOT
    # Written by Conn3x. Changes here are overwritten on the next apply.
    [nodesource-nodejs]
    name=Node.js ${var.node_major}.x from NodeSource
    baseurl=https://rpm.nodesource.com/pub_${var.node_major}.x/nodistro/nodejs/$basearch
    priority=9
    enabled=1
    gpgcheck=1
    gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-nodesource
    module_hotfixes=1
  EOT

  node_check = "node --version 2>/dev/null | grep -q '^v${var.node_major}\\.'"
}

circuit "epel" {
  hosts = local.epel_hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "release" {
    package {
      name = "epel-release"
    }
  }
}

circuit "debian" {
  hosts = { for name, h in var.hosts : name => h if local.family[name] == "debian" }

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "packages" {
    for_each = toset(["git", "tmux", "build-essential", "ripgrep", "jq", "ca-certificates"])
    package {
      name = item.value
    }
  }

  step "nodesource" {
    repository {
      name   = "nodesource"
      url    = "https://deb.nodesource.com/node_${var.node_major}.x"
      key    = file("${path.module}/files/nodesource-deb.asc")
      suites = ["nodistro"]
    }
  }

  # apt moves an older nodejs up to the repository's major when asked to
  # install it, which a package step wouldn't do.
  step "nodejs" {
    command {
      command = "DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs"
      unless  = local.node_check
    }
  }
}

circuit "redhat" {
  hosts = { for name, h in var.hosts : name => h if local.family[name] == "redhat" }

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "packages" {
    depends_on = [conn3x_package.epel__release]
    for_each   = toset(["git", "tmux", "gcc", "gcc-c++", "make", "ripgrep", "jq"])
    package {
      name = item.value
    }
  }

  # The repository step can't set the priority dnf needs, so the key and
  # the .repo file are written here.
  step "nodesource_key" {
    file {
      path    = "/etc/pki/rpm-gpg/RPM-GPG-KEY-nodesource"
      content = file("${path.module}/files/nodesource-rpm.asc")
    }
  }

  step "nodesource" {
    file {
      path    = "/etc/yum.repos.d/nodesource-nodejs.repo"
      content = local.rpm_repo
    }
  }

  # install moves an older nodejs up to the repository's major, which a
  # package step wouldn't do.
  step "nodejs" {
    command {
      command = "dnf -y --refresh install nodejs"
      unless  = local.node_check
    }
  }
}

circuit "agentbox" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # No password is set, so the account can only log in with a key.
  step "account" {
    depends_on = [conn3x_command.debian__nodejs, conn3x_command.redhat__nodejs]
    user {
      name  = local.user
      home  = local.home
      shell = "/bin/bash"
    }
  }

  step "key" {
    for_each = local.keys
    authorized_key {
      user = local.user
      key  = item.value
    }
  }

  # One step for both settings: git locks .gitconfig while it writes, so
  # two at once would fail.
  step "git_config" {
    for_each = length(local.git_config) > 0 ? { git = true } : {}
    command {
      command = join(" && ", [for k, v in local.git_config : "${local.as_user} git config --global ${k} ${v}"])
      unless  = join(" && ", [for k, v in local.git_config : "[ \"$(${local.as_user} git config --global ${k})\" = ${v} ]"])
    }
  }

  # Global npm installs go under ~/.local, which every supported
  # distribution's skeleton files put on a login shell's PATH. npm config
  # edits ~/.npmrc in place, so anything else in it stays.
  step "npm_prefix" {
    command {
      command = "${local.as_user} npm config set prefix ${local.home}/.local"
      unless  = "[ \"$(${local.as_user} npm config get prefix)\" = ${local.home}/.local ]"
    }
  }

  # One npm run for every package: two at once under the same prefix can
  # trip over each other.
  step "npm_packages" {
    for_each = length(var.npm_packages) > 0 ? { npm = true } : {}
    command {
      command = "${local.as_user} npm install -g ${join(" ", var.npm_packages)}"
      # npm ls succeeds when any one of several names is there, so each is
      # asked about on its own.
      unless = join(" && ", [for p in var.npm_packages : "${local.as_user} npm ls -g --depth=0 ${p} >/dev/null"])
    }
  }

  step "workspace" {
    for_each = var.workspace == null ? {} : { workspace = local.workspace }
    directory {
      path  = item.value
      owner = local.user
      group = local.user
      mode  = "0755"
    }
  }

  # Cloned once and then left alone. A git step would check the ref out
  # again on every apply and throw away whatever an agent changed.
  step "repos" {
    for_each = local.repos
    command {
      command = "${local.as_user} git clone -q -- '${item.value}' '${local.workspace}/${item.key}'"
      creates = "${local.workspace}/${item.key}/.git"
    }
  }
}
