# ─────────────────────────────────────────────────────────────
# 권한 (참고: fastcampus atlantis-deploy 의 ecs_task_execution · atlantis-alias-admin)
#
#   <name>-ecs_task_execution        : Atlantis 태스크 역할 (실행 + 태스크 겸용, 참고 레포와 같다)
#                                      SSM 비밀 읽기 · 상태 버킷 · sops 역할 · 아래 admin 역할 빌리기만
#   atlantis-<account_alias>-admin   : 인프라를 실제로 만드는 역할. 태스크 역할만 빌린다
#                                      참고 레포의 AdministratorAccess 대신 PowerUser + <product>-* IAM 쓰기
#   <product>-readonly               : 사람이 로컬에서 쓰는 읽기 전용 역할
# ─────────────────────────────────────────────────────────────

locals {
  iam_arn    = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}"
  state_arn  = "arn:${data.aws_partition.current.partition}:s3:::${var.tfstate_bucket}"
  managed_re = "${var.product}-*"
  sops_roles = values(data.terraform_remote_state.sops.outputs.sops_role_arns)
}

###################
# Atlantis 태스크 역할
###################
data "aws_iam_policy_document" "ecs_tasks" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.name}-ecs_task_execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.id
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_task_access" {
  # ref: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/specifying-sensitive-data.html
  statement {
    sid       = "ReadAtlantisSecrets"
    actions   = ["ssm:GetParameters"]
    resources = [for p in aws_ssm_parameter.secret : p.arn]
  }

  # backend(S3 상태)는 provider 의 assume_role 을 쓰지 않고 이 역할로 직접 읽고 쓴다
  statement {
    sid       = "TerraformStateList"
    actions   = ["s3:ListBucket"]
    resources = [local.state_arn]
  }

  statement {
    sid       = "TerraformStateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_arn}/*"]
  }

  # 인프라 적용(admin 역할)과 sops 복호화(sops 역할)
  statement {
    sid       = "AssumeRoles"
    actions   = ["sts:AssumeRole"]
    resources = concat([aws_iam_role.atlantis_admin.arn], local.sops_roles)
  }

  # ECS Exec (디버깅용 셸 접속)
  statement {
    sid = "EcsExec"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecs_task_access" {
  name   = "ECSTaskAccessPolicy"
  role   = aws_iam_role.ecs_task_execution.id
  policy = data.aws_iam_policy_document.ecs_task_access.json
}

###################
# 인프라를 만드는 역할 (참고 레포의 atlantis-alias-admin)
###################
resource "aws_iam_role" "atlantis_admin" {
  name                 = "atlantis-${var.account_alias}-admin"
  max_session_duration = 3600

  # Atlantis 태스크만 빌린다. 사람은 이 역할로 apply 하지 못한다
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.ecs_task_execution.arn }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "atlantis_admin" {
  role       = aws_iam_role.atlantis_admin.id
  policy_arn = var.terraform_role_policy_arn
}

# PowerUserAccess 는 IAM 을 거의 전부 막는다 (읽기 포함).
#   읽기 : 모든 IAM (Terraform 이 상태를 새로 고칠 때 필요)
#   쓰기 : <product>-* 역할 · 인스턴스 프로파일 · 정책, GitHub OIDC 공급자만
#   금지 : 이 역할 자신 · 읽기 전용 역할 · Atlantis 역할 (스스로 권한을 키우지 못하게)
# IAM 쓰기가 있는 한 이 역할은 사실상 관리자급이다. 이름 규칙으로 다른 역할을 건드리지 못하게 한다.
resource "aws_iam_role_policy" "atlantis_admin_iam" {
  name = "iam-management"
  role = aws_iam_role.atlantis_admin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadIam"
        Effect   = "Allow"
        Action   = ["iam:Get*", "iam:List*"]
        Resource = "*"
      },
      {
        Sid    = "ManageOwnRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateRoleDescription",
          "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:PassRole",
        ]
        Resource = ["${local.iam_arn}:role/${local.managed_re}"]
      },
      {
        Sid    = "ManageOwnInstanceProfiles"
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile", "iam:UntagInstanceProfile",
        ]
        Resource = ["${local.iam_arn}:instance-profile/${local.managed_re}"]
      },
      {
        Sid    = "ManageOwnPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
          "iam:TagPolicy", "iam:UntagPolicy",
        ]
        Resource = ["${local.iam_arn}:policy/${local.managed_re}"]
      },
      {
        Sid    = "ManageGithubOidcProvider"
        Effect = "Allow"
        Action = [
          "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider", "iam:UntagOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:AddClientIDToOpenIDConnectProvider", "iam:RemoveClientIDFromOpenIDConnectProvider",
        ]
        Resource = ["${local.iam_arn}:oidc-provider/token.actions.githubusercontent.com"]
      },
      {
        Sid    = "ProtectAtlantisRoles"
        Effect = "Deny"
        Action = [
          "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
        ]
        Resource = [
          aws_iam_role.atlantis_admin.arn,
          aws_iam_role.readonly.arn,
          "${local.iam_arn}:role/${var.name}-*",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy" "atlantis_admin_state" {
  name = "terraform-state"
  role = aws_iam_role.atlantis_admin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = [local.state_arn] },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = ["${local.state_arn}/*"] },
    ]
  })
}

###################
# 사람용 읽기 전용 역할
###################
# 로컬에서는 이 역할로 plan · output · 콘솔 조회만 한다.
#   읽기 : ReadOnlyAccess (SSM SecureString · 시크릿 값 · sops 복호화는 할 수 없다)
#   쓰기 : 상태 잠금 파일(*.tflock)만 — plan 도 잠금을 잡는다
# sops 파일을 쓰는 스택은 복호화를 못 하므로 로컬 plan 이 안 된다 (Atlantis 에서 plan 한다)
resource "aws_iam_role" "readonly" {
  name                 = "${var.product}-readonly"
  max_session_duration = 43200

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = length(var.readonly_principal_arns) > 0 ? var.readonly_principal_arns : ["${local.iam_arn}:root"]
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.readonly.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "readonly_state_lock" {
  name = "terraform-state-lock"
  role = aws_iam_role.readonly.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PlanLockOnly"
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = ["${local.state_arn}/*.tflock"]
    }]
  })
}
