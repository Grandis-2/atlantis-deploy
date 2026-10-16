# ─────────────────────────────────────────────────────────────
# 메인 ALB 로 받기 — atlantis.<도메인> → CloudFront(여기) → 메인 ALB 443(인프라 저장소) → Atlantis 태스크 4141
#
# 전용 ALB(module.alb)의 시간 요금과 공인 IP 둘을 없애려고 인프라 저장소의 메인 ALB 를 같이 쓴다.
# 메인 ALB · 리스너 · ALB SG 는 인프라 저장소 것이고, 여기서는 Atlantis 몫의 규칙 · SNI 인증서 · SG 규칙만 덧붙인다.
# 그래서 Atlantis 의 진입로는 Atlantis 가 아니라 사람이 이 저장소에서 apply 한다(Atlantis 가 자기 진입로를 바꾸지 않는다).
#
# 메인 ALB 가 CloudFront 대역 · 원본 확인 헤더만 받으므로 CloudFront 를 거친다. Host 를 그대로 넘겨 ALB 가 이 이름으로 가르고,
# 이 이름의 리전 인증서(module.acm)를 SNI 로 내준다.
# WAF 는 두지 않는다. 웹 UI 는 Basic 인증, 웹훅(/events)은 GitHub 서명으로 Atlantis 가 확인하고, 관리형 규칙이 웹훅 본문을 오탐한다.
# 대가: 메인 ALB · CloudFront 가 망가지면 Atlantis 도 닿지 않는다. 그때는 관리자가 로컬에서 고친다.
# ─────────────────────────────────────────────────────────────

locals {
  main_alb = {
    listener_arn  = data.terraform_remote_state.ecs.outputs.alb_https_listener_arn
    sg_id         = data.terraform_remote_state.security.outputs.alb_security_group_id
    verify_header = data.terraform_remote_state.ecs.outputs.origin_verify_header.name
    # remote state 로 읽은 값은 sensitive 표시가 풀린다. 다시 가린다
    verify_value = sensitive(data.terraform_remote_state.ecs.outputs.origin_verify_header.value)
  }
  log_bucket_id = data.terraform_remote_state.s3.outputs.log_bucket.id
}

# CloudFront 인증서(us-east-1). DNS 검증 레코드는 리전 인증서(module.acm)와 같은 것을 쓴다(같은 도메인이면 ACM 이 같은 값을 준다)
resource "aws_acm_certificate" "cloudfront" {
  provider = aws.us_east_1

  domain_name       = local.atlantis_fqdn
  validation_method = "DNS"

  tags = local.tags

  lifecycle {
    create_before_destroy = true

    # 검증 레코드는 리전 인증서(module.acm)가 만든 것을 같이 쓴다. 도메인이 없거나 인증서를 밖에서 넘기면 그 레코드가 없다
    precondition {
      condition     = local.use_domain && var.certificate_arn == ""
      error_message = "메인 ALB 로 받으려면 route53_zone_name 이 있고 certificate_arn 은 비워야 합니다(module.acm 의 검증 레코드를 같이 씁니다)."
    }
  }
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = module.acm.validation_route53_record_fqdns
}

# 메인 ALB 리스너의 기본 인증서는 API 것이다. Atlantis 이름은 SNI 로 더 붙인다
resource "aws_lb_listener_certificate" "main_alb" {
  listener_arn    = local.main_alb.listener_arn
  certificate_arn = local.certificate_arn
}

resource "aws_lb_target_group" "main_alb" {
  name        = "${var.name}-main"
  port        = var.atlantis_port
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  deregistration_delay = 10

  health_check {
    path    = "/healthz"
    matcher = "200"
  }

  tags = local.tags
}

# 인프라 저장소의 규칙: Grafana 1 · 브라우저 수집 2, 서비스 10~90. Host 로 가르므로 API 와 겹치지 않는다
resource "aws_lb_listener_rule" "main_alb" {
  listener_arn = local.main_alb.listener_arn
  priority     = 3

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main_alb.arn
  }

  condition {
    host_header {
      values = [local.atlantis_fqdn]
    }
  }

  condition {
    http_header {
      http_header_name = local.main_alb.verify_header
      values           = [local.main_alb.verify_value]
    }
  }

  tags = local.tags

  depends_on = [aws_lb_listener_certificate.main_alb]
}

# 메인 ALB → Atlantis 4141. 두 SG 에 규칙만 더한다(SG 자체는 각자 저장소 것)
resource "aws_vpc_security_group_ingress_rule" "atlantis_from_main_alb" {
  security_group_id            = module.atlantis_sg.id
  description                  = "Atlantis from main ALB"
  referenced_security_group_id = local.main_alb.sg_id
  ip_protocol                  = "tcp"
  from_port                    = var.atlantis_port
  to_port                      = var.atlantis_port
}

resource "aws_vpc_security_group_egress_rule" "main_alb_to_atlantis" {
  security_group_id            = local.main_alb.sg_id
  description                  = "to Atlantis tasks (atlantis-deploy)"
  referenced_security_group_id = module.atlantis_sg.id
  ip_protocol                  = "tcp"
  from_port                    = var.atlantis_port
  to_port                      = var.atlantis_port
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "atlantis" {
  #checkov:skip=CKV_AWS_68:웹 UI 는 Basic 인증, 웹훅은 GitHub 서명으로 Atlantis 가 확인한다. 관리형 규칙이 웹훅 본문을 오탐한다
  enabled         = true
  comment         = var.name
  price_class     = "PriceClass_200"
  aliases         = [local.atlantis_fqdn]
  http_version    = "http2and3"
  is_ipv6_enabled = true

  origin {
    origin_id   = "main-alb"
    domain_name = var.main_alb_origin_host

    custom_header {
      name  = local.main_alb.verify_header
      value = local.main_alb.verify_value
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 60
    }
  }

  default_cache_behavior {
    target_origin_id       = "main-alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cloudfront.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  logging_config {
    bucket          = "${local.log_bucket_id}.s3.amazonaws.com"
    prefix          = "cloudfront-atlantis/"
    include_cookies = false
  }

  tags = local.tags
}
