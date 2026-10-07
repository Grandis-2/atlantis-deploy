# atlantis-deploy

Terraform 을 적용하는 **Atlantis 자체**를 AWS Fargate 에 띄운다.
구조는 [fastcampus atlantis-deploy](https://github.com/terraform-aws-modules/terraform-aws-atlantis) 를 따르고,
모듈은 최신 메이저(alb 10 · ecs 7 · security-group 6 · acm 6)로 맞췄다.

Atlantis 가 자기 자신을 바꿀 수는 없으므로 **이 저장소만 사람이 관리자 세션으로 apply 한다.**

```
GitHub PR ──webhook──▶ ALB (https://atlantis.grandis-nova.link)
                         └─▶ ECS Fargate 태스크 1개 (nova-atlantis)
                               ├─ sts:AssumeRole ─▶ atlantis-grandis-nova-admin ─▶ 인프라 적용
                               └─ sts:AssumeRole ─▶ nova-sops-common / -secure ─▶ sops 복호화
```

## 참고 레포와 다른 점

| 항목 | 참고 레포 | 여기 |
| --- | --- | --- |
| VPC | Atlantis 전용 VPC · NAT 를 새로 만든다 | 인프라 저장소의 VPC 를 쓴다 (`vpc` 상태) |
| 비밀 | tfvars 변수로 받아 SSM 에 넣는다 | `secrets.sops.yaml`(KMS 암호화)에서 읽어 SSM SecureString 에 넣는다 |
| GitHub 인증 | PAT | PAT 또는 GitHub App (`atlantis_github_app_id` 가 있으면 App) |
| 인프라 역할 | `atlantis-alias-admin` + AdministratorAccess | `atlantis-grandis-nova-admin` + PowerUser + `nova-*` IAM 쓰기만 |
| 이미지 | `latest` | `v0.48.0` 고정 |
| 웹 UI | 인증 없음 | Basic 인증 (비밀번호는 SSM) |
| 환경변수 | `ATLANTIS_REPO_WHITELIST` 등 옛 이름 | `ATLANTIS_REPO_ALLOWLIST` · `ATLANTIS_REPO_CONFIG_JSON` |

## 인프라 저장소와 같아야 하는 값

인프라 저장소는 `Grandis-2/nova-infra` 다 (Atlantis 가 PR 을 받는 저장소, `atlantis_repo_allowlist`). 아래 명령의 `../nova-infra` 는 그 저장소를 받아 둔 로컬 폴더다 (두 저장소를 나란히 둔다).

| 값 | 이 저장소 | 인프라 저장소 |
| --- | --- | --- |
| `product` · `env` · `aws_region` · `tfstate_bucket` | `terraform.tfvars` | `terraform/_global/global.auto.tfvars` |
| 상태 버킷 · 리전 | `backend.hcl` | `.env` 의 `TF_BACKEND_*` |
| sops 키 · 역할 | `.sops.yaml` (secure) | `terraform/aws/kms/grandis-nova/ap-northeast-2` 가 만든다 |

## 처음 올리는 순서

관리자 세션으로 진행한다 (인프라 저장소 `docs/setup.md` A — 이 README 는 A-5 ~ A-7 의 자세한 판).

```bash
unset AWS_PROFILE   # 프로필이 남아 있으면 Terraform 이 관리자 세션 대신 그쪽을 쓴다
eval "$(aws configure export-credentials --profile infra-admin --format env)"
export TF_ALLOW_LOCAL_WRITE=1
aws sts get-caller-identity   # assumed-role/BreakGlassAdmin/… 이어야 한다

# 1) 인프라 저장소: 상태 버킷 → sops 키 → VPC
cd ../nova-infra
./scripts/bootstrap.sh
./scripts/tf.sh aws/kms/grandis-nova/ap-northeast-2 init && ./scripts/tf.sh aws/kms/grandis-nova/ap-northeast-2 apply
./scripts/tf.sh aws/vpc/prod init && ./scripts/tf.sh aws/vpc/prod apply

# 2) 이 저장소: 비밀 파일 만들기 (.sops.yaml 의 kms 값이 kms 스택 출력 secure 와 같은지 확인)
cd ../atlantis-deploy
# .sops.yaml 규칙은 파일 이름으로 고른다. secrets.sops.yaml 로 만들고 제자리에서 암호화한다
cat > secrets.sops.yaml <<'YAML'
github_token: <PAT 방식일 때 봇 계정 토큰>
# github_app_key: |          ← App 방식일 때 개인키(PEM) 전체
#   -----BEGIN RSA PRIVATE KEY-----
#   ...
ncloud_access_key: <NCP Sub Account Access Key>
ncloud_secret_key: <NCP Sub Account Secret Key>
YAML
sops --encrypt --in-place secrets.sops.yaml
# 수정할 때는 sops secrets.sops.yaml (편집기에서 평문으로 열리고 저장 시 다시 암호화)

# 3) Atlantis
terraform init -backend-config=backend.hcl
terraform apply
terraform output -raw atlantis_url_events      # GitHub 웹훅 URL
terraform output -raw webhook_secret           # GitHub 웹훅 secret
```

4. **GitHub 연결**
   - App 방식: App 설정의 Webhook URL · secret 에 위 두 값을 넣는다
   - PAT 방식: 인프라 저장소 Settings → Webhooks 에 넣는다 (또는 `modules/github-repository-webhook`)
5. 인프라 저장소에 테스트 PR → `atlantis plan` 댓글이 달리면 끝

`secrets.sops.yaml` 이 없으면 비밀이 `CHANGE_ME` 로 들어가고 plan 에 경고가 뜬다. 그 상태로 Atlantis 는 GitHub 에 붙지 못한다.

## 근무 시간에만 뜬다

태스크(0.5 vCPU · 2 GB)는 **평일 09:00 ~ 22:00(KST)에만 1개**, 밤 · 주말에는 0개다 (`schedule_*` 변수).

- 0개인 동안은 Atlantis 가 **아예 없다**. GitHub 웹훅은 ALB 에서 503 으로 끝나고, GitHub 은 다시 보내지 않는다
- 켜진 뒤 PR 에 `atlantis plan` 댓글을 달면 그때 plan 한다 (App 이면 App 설정 → Advanced → Recent Deliveries 에서 다시 보내도 된다)
- 진행 중이던 plan · 잠금은 태스크가 내려갈 때 사라진다. 22시 전에 apply 를 끝낸다
- ALB 는 계속 떠 있으므로 ALB 요금은 그대로 나간다

**급할 때 켜기 · 끄기** (다음 예약 시각이 오면 다시 예약대로 돌아간다)

```bash
# 켜기
aws application-autoscaling register-scalable-target --service-namespace ecs \
  --resource-id service/nova-atlantis/nova-atlantis --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 1 --max-capacity 1
# 끄기 — 위 명령에서 1 을 0 으로
```

예약을 끄고 항상 띄우려면 `terraform.tfvars` 에 `schedule_enabled = false` 를 넣고 apply 한다.

## 비밀 바꾸기

```bash
sops secrets.sops.yaml          # 값 수정
terraform apply                 # SSM 갱신
aws ecs update-service --cluster nova-atlantis --service nova-atlantis --force-new-deployment
```

## 웹 UI

```bash
aws ssm get-parameter --with-decryption --name "$(terraform output -raw web_password_parameter)" \
  --query Parameter.Value --output text      # 사용자 이름: atlantis
```
