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

# ACM · Route53
variable "route53_zone_name" {
  description = "Route53 zone name (without trailing dot). Atlantis 주소 atlantis_hostname.<이 영역> 의 CloudFront 별칭 · 인증서 · 메인 ALB 규칙에 쓴다"
  type        = string

  # 전용 ALB 가 없어 도메인 없이 받을 길이 없다
  validation {
    condition     = trimspace(var.route53_zone_name) != ""
    error_message = "route53_zone_name 은 비울 수 없습니다. Atlantis 는 CloudFront → 메인 ALB 로만 받습니다."
  }
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
  description = "sops 로 암호화한 비밀 파일 (github_app_key, ncloud_access_key, ncloud_secret_key)"
  type        = string
  default     = "secrets.sops.yaml"
}

# ECS Service / Task
variable "ecs_task_cpu" {
  description = "The number of cpu units used by the task (512 = 0.5 vCPU)"
  type        = number
  default     = 512
}

variable "ecs_task_memory" {
  description = "The amount (in MiB) of memory used by the task. plan 이 동시에 여러 개 돌면 provider 마다 수백 MB 를 쓴다"
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

# GitHub App — 개인키는 secrets.sops.yaml 의 github_app_key
variable "atlantis_github_app_id" {
  description = "GitHub App ID"
  type        = string
}

variable "atlantis_github_app_slug" {
  description = "GitHub App 슬러그 (Atlantis 가 자기 댓글을 알아보는 데 쓴다)"
  type        = string
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

variable "main_alb_origin_host" {
  description = "CloudFront 가 메인 ALB 에 붙을 때 쓰는 이름(인프라 저장소 edge 스택의 origin.<API 도메인>). ALB 인증서에 이 이름이 있다"
  type        = string
  default     = "origin.api.grandis-nova.link"
}
