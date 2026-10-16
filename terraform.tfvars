# ── 인프라 저장소와 같아야 하는 값 ─────────────────────────────
product        = "nova"
env            = "prod"
aws_region     = "ap-northeast-2"
account_alias  = "grandis-nova"
tfstate_bucket = "grandis-nova-prod-apnortheast2-tfstate"

# ── 이름 · 도메인 ────────────────────────────────────────────
name              = "nova-atlantis"
route53_zone_name = "grandis-nova.link" # Route 53 호스팅 영역이 있어야 한다
atlantis_hostname = "atlantis"          # → https://atlantis.grandis-nova.link

# ── Atlantis ────────────────────────────────────────────────
atlantis_version        = "v0.48.0"
atlantis_repo_allowlist = ["github.com/Grandis-2/nova-infra"] # 인프라 저장소. 조직을 옮기면 바꾼다

# GitHub App. 개인키는 secrets.sops.yaml 의 github_app_key
atlantis_github_app_id   = "5221487"
atlantis_github_app_slug = "nova-atlantis"

tags = {
  Name = "nova-atlantis"
}
