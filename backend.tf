# Atlantis 자체의 상태. 애플리케이션 인프라와 같은 버킷을 쓰되 키를 분리한다.
#
# 닭과 달걀: Atlantis 를 만드는 이 스택만은 Atlantis 가 적용할 수 없다.
# 사람이 로컬에서 apply 한다.
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key          = "prod/atlantis/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
