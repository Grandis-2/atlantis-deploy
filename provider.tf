# 이 저장소는 사람(관리자 세션)만 apply 한다. Atlantis 가 자기 자신을 바꿀 수는 없다.
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Product   = var.product
      Env       = var.env
      ManagedBy = "terraform"
      Stack     = "atlantis"
    }
  }
}

# secrets.sops.yaml 을 푼다. 파일 메타데이터의 역할(nova-sops-secure)을 빌려 KMS 로 복호화한다
provider "sops" {}
