variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file, jump_hosts or os."

  validation {
    condition     = alltrue([for h in var.hosts : contains(["debian", "ubuntu", "rocky", "almalinux", "rhel", "fedora"], try(h.os, "debian"))])
    error_message = "A host object's os must be one of debian, ubuntu, rocky, almalinux, rhel or fedora. CentOS Linux reached end of life on 30 June 2024: use Rocky Linux."
  }
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}
variable "user" {
  type        = string
  default     = "dev"
  description = "Login name of the account you and your agents work as. Its home is /home/USER."

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.user)) && var.user != "root"
    error_message = "user starts with a lowercase letter or _, followed by up to 31 lowercase letters, digits, - or _, and can't be root."
  }
}

variable "ssh_keys" {
  type        = list(string)
  description = "Public keys that can log in as user, in authorized_keys format, such as [file(\"~/.ssh/id_ed25519.pub\")]."

  validation {
    condition     = length(var.ssh_keys) > 0
    error_message = "ssh_keys needs at least one public key. The account has no password, so without a key nobody can log in as it."
  }
}

variable "git_name" {
  type        = string
  default     = null
  description = "git's user.name for user, which commits are made under. When null, left as it is."

  validation {
    condition     = var.git_name == null || (trimspace(coalesce(var.git_name, "-")) != "" && !strcontains(coalesce(var.git_name, "-"), "\n"))
    error_message = "git_name must be a single line and not empty."
  }
}

variable "git_email" {
  type        = string
  default     = null
  description = "git's user.email for user. When null, left as it is."

  validation {
    condition     = var.git_email == null || can(regex("^[^\\s@]+@[^\\s@]+$", coalesce(var.git_email, "-")))
    error_message = "git_email must be an email address, such as \"you@example.com\"."
  }
}

variable "node_major" {
  type        = number
  default     = 26
  description = "Node.js major release to install from NodeSource. 26 is the current LTS release."

  validation {
    condition     = var.node_major >= 20 && floor(var.node_major) == var.node_major
    error_message = "node_major must be a whole Node.js major release, 20 or later."
  }
}

variable "npm_packages" {
  type        = list(string)
  default     = []
  description = "npm packages to install globally as user, such as [\"@anthropic-ai/claude-code\", \"@openai/codex\"]. Nothing is installed by default."

  validation {
    condition     = alltrue([for p in var.npm_packages : can(regex("^(@[a-z0-9][a-z0-9._~-]*/)?[a-z0-9][a-z0-9._~-]*$", p))])
    error_message = "Each of npm_packages must be an npm package name, such as \"@openai/codex\", without a version."
  }
}

variable "workspace" {
  type        = string
  default     = null
  description = "Directory for your checkouts, owned by user: relative to the home directory, such as \"code\", or absolute. When null, repos are cloned into the home directory."

  validation {
    condition     = var.workspace == null || can(regex("^/?[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$", coalesce(var.workspace, "-"))) && !contains(split("/", coalesce(var.workspace, "-")), "..")
    error_message = "workspace is a path such as \"code\" or \"/srv/work\", with letters, digits, ., _ and - in each part, and no \"..\"."
  }
}

variable "repos" {
  type        = list(string)
  default     = []
  description = "Repositories to clone once into workspace over HTTPS, such as [\"https://github.com/example/app.git\"]. Each lands in a directory named after the repository."

  validation {
    condition     = alltrue([for r in var.repos : can(regex("^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~-]+)+$", r))])
    error_message = "Each of repos must be an https:// URL with no user name or password in it, such as \"https://github.com/example/app.git\"."
  }

  validation {
    condition     = length(distinct([for r in var.repos : trimsuffix(basename(r), ".git")])) == length(var.repos)
    error_message = "Two repos would clone into the same directory. Each repository's name must be different."
  }
}
