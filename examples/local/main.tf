variable "port" {
  type    = number
  default = 2290
}

module "agentbox" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  # The key up.sh made for root logs in as dev too.
  user      = "dev"
  ssh_keys  = [file("./id_ed25519.pub")]
  git_name  = "Dev Box"
  git_email = "dev@example.com"

  # cowsay and semver stand in for coding agents: they install the same way
  # and need no account. On a real box, list "@anthropic-ai/claude-code",
  # "@openai/codex" or "@google/gemini-cli".
  npm_packages = ["cowsay", "semver"]

  workspace = "code"
  repos     = ["https://github.com/octocat/Hello-World.git"]
}
