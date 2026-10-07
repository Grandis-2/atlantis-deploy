# 인프라 저장소의 스택 상태를 읽는다 (상태 버킷으로만 이어진다)
locals {
  remote_state = {
    vpc  = { bucket = var.tfstate_bucket, region = var.aws_region, key = "${var.env}/vpc/terraform.tfstate" }
    sops = { bucket = var.tfstate_bucket, region = var.aws_region, key = "${var.env}/sops/terraform.tfstate" }
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
