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

# GitHub 인증 — 둘 중 하나만 채운다 (docs: PAT 와 GitHub App 비교)
#   PAT : 봇 계정 이름. 토큰은 secrets.sops.yaml 의 github_token
#   App : App ID · 슬러그. 개인키는 secrets.sops.yaml 의 github_app_key
# atlantis_github_user = ""
atlantis_github_app_id   = "5221487"
atlantis_github_app_slug = "nova-atlantis"

# ALB 접근 대역. GitHub 웹훅 대역으로 좁히려면 https://api.github.com/meta 의 hooks
# alb_ingress_cidr_blocks = ["192.30.252.0/22", "185.199.108.0/22", "140.82.112.0/20"]

tags = {
  Name = "nova-atlantis"
}
