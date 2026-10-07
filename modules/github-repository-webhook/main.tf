# 저장소에 Atlantis 웹훅을 만든다 (참고: fastcampus modules/github-repository-webhook)
# PAT(봇 계정) 방식에서만 쓴다. GitHub App 은 App 설정에 웹훅이 있어 필요 없다.
# GITHUB_TOKEN 환경변수(admin:repo_hook 권한)가 있어야 한다.
terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }
}

resource "github_repository_webhook" "this" {
  count = var.create_github_repository_webhook ? length(var.atlantis_allowed_repo_names) : 0

  repository = var.atlantis_allowed_repo_names[count.index]

  configuration {
    url          = var.webhook_url
    content_type = "application/json"
    insecure_ssl = false
    secret       = var.webhook_secret
  }

  events = [
    "issue_comment",
    "pull_request",
    "pull_request_review",
    "pull_request_review_comment",
    "push",
  ]
}
