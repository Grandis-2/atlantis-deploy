variable "create_github_repository_webhook" {
  description = "Whether to create Github repository webhook for Atlantis"
  type        = bool
  default     = true
}

variable "atlantis_allowed_repo_names" {
  description = "List of names of repositories which belong to the owner specified in the github provider"
  type        = list(string)
}

variable "webhook_url" {
  description = "Webhook URL (atlantis_url_events)"
  type        = string
}

variable "webhook_secret" {
  description = "Webhook secret"
  type        = string
  sensitive   = true
}
