output "user" {
  description = "The account the circuit sets up."
  value       = var.user
}

output "workspace" {
  description = "Directory the repositories are cloned into."
  value       = local.workspace
}

output "repos" {
  description = "Path of each cloned repository, by name."
  value       = { for name in keys(local.repos) : name => "${local.workspace}/${name}" }
}
