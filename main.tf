# ─────────────────────────────────────────────────────────────
# Atlantis on AWS Fargate (참고: fastcampus atlantis-deploy, 모듈은 최신 메이저)
#
#   ALB(HTTPS, atlantis.<도메인>) → ECS Fargate 태스크 1개 → 인프라 저장소 PR plan/apply
#
# 참고 레포와 다른 점
#   - VPC 를 새로 만들지 않고 인프라 저장소의 VPC 를 쓴다 (NAT 를 한 벌 더 두지 않는다)
#   - 비밀은 sops 파일(secrets.sops.yaml)에서 읽어 SSM SecureString 에 넣는다 (변수 · tfvars 에 두지 않는다)
#   - 인프라를 만드는 역할은 AdministratorAccess 가 아니라 PowerUser + <product>-* IAM 쓰기로 좁힌다 (iam.tf)
#   - 웹 UI 에 Basic 인증을 건다
# ─────────────────────────────────────────────────────────────

locals {
  # VPC — 인프라 저장소 vpc 스택
  vpc_id             = data.terraform_remote_state.vpc.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.vpc.outputs.app_subnet_ids
  public_subnet_ids  = data.terraform_remote_state.vpc.outputs.public_subnet_ids

  # Atlantis
  atlantis_image = var.atlantis_image == "" ? "ghcr.io/runatlantis/atlantis:${var.atlantis_version}" : var.atlantis_image

  # 도메인이 있으면 HTTPS(atlantis.<도메인>), 없으면 ALB 주소로 HTTP
  use_domain      = var.route53_zone_name != ""
  atlantis_fqdn   = local.use_domain ? "${var.atlantis_hostname}.${var.route53_zone_name}" : ""
  certificate_arn = var.certificate_arn != "" ? var.certificate_arn : module.acm.acm_certificate_arn
  use_https       = local.use_domain || var.certificate_arn != ""

  atlantis_url        = local.use_domain ? "https://${local.atlantis_fqdn}" : "http://${module.alb.dns_name}"
  atlantis_url_events = "${local.atlantis_url}/events"

  # 비밀 — sops 파일이 없으면(로컬 에뮬레이터 시험 등) 자리값을 넣는다
  secrets = fileexists("${path.module}/${var.secrets_file}") ? data.sops_file.secrets[0].data : {}

  ssm_secrets = merge(
    {
      "github/app/key" = lookup(local.secrets, "github_app_key", "CHANGE_ME")
      "webhook/secret" = random_id.webhook.hex
      "web/password"   = random_password.web.result
    },
    # NCP(ncp/* 스택)용 인증키
    {
      "ncloud/access_key" = lookup(local.secrets, "ncloud_access_key", "CHANGE_ME")
      "ncloud/secret_key" = lookup(local.secrets, "ncloud_secret_key", "CHANGE_ME")
    },
  )

  # 서버 쪽 저장소 설정: 저장소의 atlantis.yaml 이 apply_requirements 만 바꿀 수 있게 한다.
  # 커스텀 workflow(임의 명령)는 막는다.
  repo_config = {
    repos = [{
      id                     = "/.*/"
      allowed_overrides      = ["apply_requirements"]
      allow_custom_workflows = false
    }]
  }

  # Container definitions
  container_definition_environment = concat(
    [
      { name = "ATLANTIS_ATLANTIS_URL", value = local.atlantis_url },
      { name = "ATLANTIS_PORT", value = tostring(var.atlantis_port) },
      { name = "ATLANTIS_LOG_LEVEL", value = "info" },
      { name = "ATLANTIS_REPO_ALLOWLIST", value = join(",", var.atlantis_repo_allowlist) },
      { name = "ATLANTIS_REPO_CONFIG_JSON", value = jsonencode(local.repo_config) },
      # PR 브랜치를 main 과 합친 상태로 plan 한다 (그 사이 main 의 변경을 되돌리지 않게)
      { name = "ATLANTIS_CHECKOUT_STRATEGY", value = "merge" },
      { name = "ATLANTIS_HIDE_PREV_PLAN_COMMENTS", value = "true" },
      # main 브랜치 보호가 atlantis/apply 체크를 요구하면 apply 전 PR 은 늘 "blocked" 라 mergeable 요건을 못 넘는다.
      # mergeable 을 판단할 때 atlantis/apply 체크만 빼고 본다 (Atlantis 문서 command-requirements 권장)
      { name = "ATLANTIS_GH_ALLOW_MERGEABLE_BYPASS_APPLY", value = "true" },
      { name = "ATLANTIS_WEB_BASIC_AUTH", value = "true" },
      { name = "ATLANTIS_WEB_USERNAME", value = var.web_username },
      # 인프라 스택의 provider 가 이 역할을 빌린다. 세션 이름은 atlantis_user
      { name = "TF_VAR_assume_role_arn", value = aws_iam_role.atlantis_admin.arn },
      { name = "TF_VAR_terraform_actor", value = var.atlantis_user },
      # backend 블록에는 변수를 못 쓴다. init 때 버킷 · 리전을 붙여 준다
      { name = "TF_CLI_ARGS_init", value = "-backend-config=bucket=${var.tfstate_bucket} -backend-config=region=${var.aws_region}" },
      { name = "AWS_REGION", value = var.aws_region },
    ],
    # GitHub App 으로 인증한다 (개인키는 SSM github/app/key)
    [
      { name = "ATLANTIS_GH_APP_ID", value = var.atlantis_github_app_id },
      { name = "ATLANTIS_GH_APP_SLUG", value = var.atlantis_github_app_slug },
      { name = "ATLANTIS_WRITE_GIT_CREDS", value = "true" },
    ],
  )

  container_definition_secrets = [
    { name = "ATLANTIS_GH_APP_KEY", valueFrom = aws_ssm_parameter.secret["github/app/key"].arn },
    { name = "ATLANTIS_GH_WEBHOOK_SECRET", valueFrom = aws_ssm_parameter.secret["webhook/secret"].arn },
    { name = "ATLANTIS_WEB_PASSWORD", valueFrom = aws_ssm_parameter.secret["web/password"].arn },
    { name = "NCLOUD_ACCESS_KEY", valueFrom = aws_ssm_parameter.secret["ncloud/access_key"].arn },
    { name = "NCLOUD_SECRET_KEY", valueFrom = aws_ssm_parameter.secret["ncloud/secret_key"].arn },
  ]

  tags = merge({ Name = var.name }, var.tags)
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_route53_zone" "this" {
  count = local.use_domain ? 1 : 0

  name         = var.route53_zone_name
  private_zone = false
}

###################
# Secrets (sops → SSM SecureString)
###################
data "sops_file" "secrets" {
  count = fileexists("${path.module}/${var.secrets_file}") ? 1 : 0

  source_file = "${path.module}/${var.secrets_file}"
}

# 비밀 파일이 없으면 자리값으로 뜬다. 실제 배포에서 이걸 놓치지 않게 경고한다
check "secrets_file" {
  assert {
    condition     = fileexists("${path.module}/${var.secrets_file}")
    error_message = "${var.secrets_file} 이 없습니다. GitHub · NCP 비밀이 자리값(CHANGE_ME)으로 들어갑니다. README 의 sops 절차를 따르세요."
  }
}

resource "random_id" "webhook" {
  byte_length = 32
}

resource "random_password" "web" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "secret" {
  for_each = local.ssm_secrets

  name  = "${var.ssm_parameter_prefix}/${each.key}"
  type  = "SecureString"
  value = each.value

  tags = local.tags
}

###################
# ALB
###################
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "10.5.1"

  name = var.name

  vpc_id                     = local.vpc_id
  subnets                    = local.public_subnet_ids
  enable_deletion_protection = false
  drop_invalid_header_fields = true

  security_group_ingress_rules = merge(
    { for i, cidr in var.alb_ingress_cidr_blocks : "http_${i}" => { from_port = 80, to_port = 80, ip_protocol = "tcp", cidr_ipv4 = cidr } },
    local.use_https ? { for i, cidr in var.alb_ingress_cidr_blocks : "https_${i}" => { from_port = 443, to_port = 443, ip_protocol = "tcp", cidr_ipv4 = cidr } } : {},
  )
  security_group_egress_rules = {
    vpc = {
      ip_protocol = "-1"
      cidr_ipv4   = data.terraform_remote_state.vpc.outputs.vpc_cidr
    }
  }

  # 도메인이 있으면 HTTPS + HTTP→HTTPS 리다이렉트, 없으면 HTTP 로 바로 넘긴다
  listeners = merge(
    local.use_https ? {
      https = {
        port            = 443
        protocol        = "HTTPS"
        ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
        certificate_arn = local.certificate_arn
        forward         = { target_group_key = "atlantis" }
      }
    } : {},
    {
      http = {
        port     = 80
        protocol = "HTTP"
        forward  = local.use_https ? null : { target_group_key = "atlantis" }
        redirect = local.use_https ? { port = "443", protocol = "HTTPS", status_code = "HTTP_301" } : null
      }
    },
  )

  target_groups = {
    atlantis = {
      protocol             = "HTTP"
      port                 = var.atlantis_port
      target_type          = "ip"
      deregistration_delay = 10
      create_attachment    = false # ECS 서비스가 태스크를 붙인다

      health_check = {
        path    = "/healthz"
        matcher = "200"
      }
    }
  }

  route53_records = local.use_domain ? {
    atlantis = {
      zone_id = data.aws_route53_zone.this[0].zone_id
      name    = var.atlantis_hostname
      type    = "A"
    }
  } : null

  tags = local.tags
}

###################
# Security groups
###################
module "atlantis_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  name        = var.name
  vpc_id      = local.vpc_id
  description = "Security group with open port for Atlantis (${var.atlantis_port}) from ALB, egress ports are all world open"

  ingress_rules = {
    atlantis = {
      from_port                    = var.atlantis_port
      to_port                      = var.atlantis_port
      ip_protocol                  = "tcp"
      description                  = "Atlantis"
      referenced_security_group_id = module.alb.security_group_id
    }
  }

  egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "github, terraform registry, aws api, ncp api"
    }
  }

  tags = local.tags
}

###################
# ACM (SSL certificate)
###################
module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "6.3.1"

  create_certificate = local.use_domain && var.certificate_arn == ""

  domain_name       = local.atlantis_fqdn
  zone_id           = local.use_domain ? data.aws_route53_zone.this[0].zone_id : ""
  validation_method = "DNS"

  tags = local.tags
}

###################
# ECS
###################
module "ecs" {
  source  = "terraform-aws-modules/ecs/aws//modules/cluster"
  version = "7.6.1"

  name = var.name

  cluster_capacity_providers = ["FARGATE"]
  default_capacity_provider_strategy = {
    FARGATE = { weight = 1 }
  }

  # 모듈 기본값은 Container Insights 켜기다. 태스크 하나라 무료 AWS/ECS 지표로 충분하고, 켜면 사용자 지정 지표로 과금된다
  setting = [{ name = "containerInsights", value = "disabled" }]

  # Fargate 태스크 하나라 클러스터 부가 리소스는 만들지 않는다
  create_cloudwatch_log_group      = false
  create_security_group            = false
  create_infrastructure_iam_role   = false
  create_node_iam_instance_profile = false

  tags = local.tags
}

module "container_definition" {
  source  = "cloudposse/ecs-container-definition/aws"
  version = "0.61.2"

  container_name  = var.name
  container_image = local.atlantis_image

  container_cpu    = var.ecs_task_cpu
  container_memory = var.ecs_task_memory

  port_mappings = [
    {
      containerPort = var.atlantis_port
      hostPort      = var.atlantis_port
      protocol      = "tcp"
    },
  ]

  log_configuration = {
    logDriver = "awslogs"
    options = {
      "awslogs-region"        = data.aws_region.current.region
      "awslogs-group"         = aws_cloudwatch_log_group.atlantis.name
      "awslogs-stream-prefix" = "ecs"
    }
  }

  environment = concat(local.container_definition_environment, var.custom_environment_variables)
  secrets     = concat(local.container_definition_secrets, var.custom_environment_secrets)
}

resource "aws_ecs_task_definition" "atlantis" {
  family                   = var.name
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_execution.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory

  container_definitions = module.container_definition.json_map_encoded_list

  tags = local.tags
}

resource "aws_ecs_service" "atlantis" {
  name            = var.name
  cluster         = module.ecs.id
  task_definition = aws_ecs_task_definition.atlantis.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # 잠금 정보를 태스크 안에 두므로 두 개가 동시에 뜨지 않게 한다
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  enable_execute_command = true

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [module.atlantis_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    container_name   = var.name
    container_port   = var.atlantis_port
    target_group_arn = module.alb.target_groups["atlantis"].arn
  }

  health_check_grace_period_seconds = 120

  # 태스크 수는 아래 예약 작업(근무 시간 1 · 그 외 0)이 정한다
  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = local.tags
}

###################
# Cloudwatch logs
###################
resource "aws_cloudwatch_log_group" "atlantis" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.cloudwatch_log_retention_in_days

  tags = local.tags
}
