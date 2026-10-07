# 인프라 저장소 terraform/_global/global.auto.tfvars 와 같은 값을 쓴다 (terraform.tfvars)
variable "aws_region" {
  default = "ap-northeast-2"
}

variable "product" {
  description = "리소스 이름 접두사"
  default     = "nova"
}

variable "env" {
  default = "prod"
}

variable "account_alias" {
  description = "계정 별칭 (참고 레포의 zerone-id 에 해당)"
  default     = "grandis-nova"
}

variable "tfstate_bucket" {
  description = "상태 버킷. 인프라 저장소의 init 스택이 만든다"
  type        = string
}

# Atlantis 가 인프라 스택을 적용할 때 쓰는 세션 이름 (참고 레포의 atlantis_user)
variable "atlantis_user" {
  default = "atlantis"
}
