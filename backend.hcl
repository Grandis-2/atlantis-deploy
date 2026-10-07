# terraform init -backend-config=backend.hcl
# 인프라 저장소의 상태 버킷과 같다 (terraform/_global/global.auto.tfvars 의 tfstate_bucket)
bucket = "grandis-nova-prod-apnortheast2-tfstate"
region = "ap-northeast-2"
