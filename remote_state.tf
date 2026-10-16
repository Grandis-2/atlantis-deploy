# 인프라 저장소의 스택 상태를 읽는다 (상태 버킷으로만 이어진다)
locals {
  remote_state = {
    vpc  = { bucket = var.tfstate_bucket, region = var.aws_region, key = "${var.env}/vpc/terraform.tfstate" }
    sops = { bucket = var.tfstate_bucket, region = var.aws_region, key = "${var.env}/sops/terraform.tfstate" }
    # 메인 ALB 로 받기 위해 읽는다(main_alb.tf). 그 리소스는 인프라 저장소가 만들고, 여기서는 규칙 · SG 규칙만 덧붙인다
    ecs      = { bucket = var.tfstate_bucket, region = var.aws_region, key = "${var.env}/ecs/terraform.tfstate" }
    security = { bucket = var.tfstate_bucket, region = var.aws_region, key = "${var.env}/security/terraform.tfstate" }
    s3       = { bucket = var.tfstate_bucket, region = var.aws_region, key = "${var.env}/s3/terraform.tfstate" }
  }
}

# Atlantis 는 애플리케이션과 같은 VPC 에 뜬다 (전용 VPC · NAT 를 따로 두지 않는다)
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config  = local.remote_state.vpc
}

# sops 역할 — 태스크 역할이 빌려 비밀 파일을 복호화한다
data "terraform_remote_state" "sops" {
  backend = "s3"
  config  = local.remote_state.sops
}

# 메인 ALB 의 HTTPS 리스너 · 원본 확인 헤더
data "terraform_remote_state" "ecs" {
  backend = "s3"
  config  = local.remote_state.ecs
}

# 메인 ALB SG
data "terraform_remote_state" "security" {
  backend = "s3"
  config  = local.remote_state.security
}

# 로그 버킷(CloudFront 접근 로그)
data "terraform_remote_state" "s3" {
  backend = "s3"
  config  = local.remote_state.s3
}
