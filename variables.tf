variable "name" {
  description = "Name to use on all resources created (ALB, ECS, IAM 등)"
  type        = string
  default     = "nova-atlantis"
}

variable "tags" {
  description = "A map of tags to use on all resources"
  type        = map(string)
  default     = {}
}

# ALB
variable "alb_ingress_cidr_blocks" {
  description = "List of IPv4 CIDR ranges to use on all ingress rules of the ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ACM · Route53
variable "route53_zone_name" {
  description = "Route53 zone name (without trailing dot). 비우면 도메인 · 인증서 없이 ALB 주소로 HTTP 만 받는다"
  type        = string
  default     = ""
}

variable "atlantis_hostname" {
  description = "Atlantis 호스트 이름 (route53_zone_name 아래). 예: atlantis → atlantis.grandis-nova.link"
  type        = string
  default     = "atlantis"
}

variable "certificate_arn" {
  description = "ARN of an existing ACM certificate. 비우면 Route53 DNS 검증으로 새로 만든다"
  type        = string
  default     = ""
}

# Cloudwatch
variable "cloudwatch_log_retention_in_days" {
  description = "Retention period of Atlantis CloudWatch logs"
  type        = number
  default     = 14
}

# SSM parameters for secrets
variable "ssm_parameter_prefix" {
  description = "Atlantis 비밀을 둘 SSM 파라미터 경로 접두사"
  type        = string
  default     = "/nova-atlantis"
}

variable "secrets_file" {
  description = "sops 로 암호화한 비밀 파일 (github_token 또는 github_app_key, ncloud_access_key, ncloud_secret_key)"
  type        = string
  default     = "secrets.sops.yaml"
}

# ECS Service / Task
variable "ecs_task_cpu" {
  description = "The number of cpu units used by the task. plan 을 여러 스택 동시에 돌리므로 넉넉히"
  type        = number
  default     = 1024
}

variable "ecs_task_memory" {
  description = "The amount (in MiB) of memory used by the task"
  type        = number
  default     = 2048
}

# Atlantis
variable "atlantis_image" {
  description = "Docker image to run Atlantis with. If not specified, official Atlantis image will be used"
  type        = string
  default     = ""
}

variable "atlantis_version" {
  description = "Version of Atlantis to run. latest 를 쓰지 않는다 (예기치 않은 업그레이드 방지)"
  type        = string
  default     = "v0.48.0"
}

variable "atlantis_port" {
  description = "Local port Atlantis should be running on."
  type        = number
  default     = 4141
}

variable "atlantis_repo_allowlist" {
  description = "List of allowed repositories Atlantis can be used with (예: github.com/Grandis-2/nova-infra)"
  type        = list(string)
}

variable "atlantis_allowed_repo_names" {
  description = "웹훅을 코드로 만들 GitHub 저장소 이름 (PAT 방식에서 modules/github-repository-webhook 를 쓸 때)"
  type        = list(string)
  default     = []
}

# GitHub — PAT(봇 계정) 또는 GitHub App 중 하나
variable "atlantis_github_user" {
  description = "PAT 방식: Atlantis 가 쓰는 GitHub 봇 계정 이름. 토큰은 secrets.sops.yaml 의 github_token"
  type        = string
  default     = ""
}

variable "atlantis_github_app_id" {
  description = "App 방식: GitHub App ID. 개인키는 secrets.sops.yaml 의 github_app_key"
  type        = string
  default     = ""
}

variable "atlantis_github_app_slug" {
  description = "App 방식: GitHub App 슬러그 (Atlantis 가 자기 댓글을 알아보는 데 쓴다)"
  type        = string
  default     = ""
}

variable "web_username" {
  description = "Atlantis 웹 UI Basic 인증 사용자 이름 (잠금 해제 같은 조작을 막는다)"
  type        = string
  default     = "atlantis"
}

variable "custom_environment_variables" {
  description = "List of additional environment variables the container will use (list should contain maps with `name` and `value`)"
  type        = list(map(string))
  default     = []
}

variable "custom_environment_secrets" {
  description = "List of additional secrets the container will use (list should contain maps with `name` and `valueFrom`)"
  type        = list(map(string))
  default     = []
}

# 인프라 스택을 만드는 역할
variable "terraform_role_policy_arn" {
  description = "Atlantis 가 빌리는 Terraform 역할에 붙일 정책 (IAM 쓰기는 iam.tf 에서 <product>-* 로 좁힌다)"
  type        = string
  default     = "arn:aws:iam::aws:policy/PowerUserAccess"
}

variable "readonly_principal_arns" {
  description = "읽기 전용 역할을 빌릴 수 있는 IAM 주체 ARN. 비우면 계정 루트(= 각자의 IAM 정책이 허용한 주체)"
  type        = list(string)
  default     = []
}
