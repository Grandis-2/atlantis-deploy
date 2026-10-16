output "atlantis_url" {
  description = "URL of Atlantis"
  value       = local.atlantis_url
}

output "atlantis_url_events" {
  description = "Webhook events URL of Atlantis (GitHub App 의 Webhook URL)"
  value       = local.atlantis_url_events
}

output "task_role_arn" {
  description = "The Atlantis ECS task role arn"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "atlantis_admin_role_arn" {
  description = "Atlantis 가 인프라를 적용할 때 빌리는 역할 (컨테이너에 TF_VAR_assume_role_arn 로 들어간다)"
  value       = aws_iam_role.atlantis_admin.arn
}

output "readonly_role_arn" {
  description = "사람이 로컬에서 쓰는 읽기 전용 역할. ~/.aws/config 프로필의 role_arn"
  value       = aws_iam_role.readonly.arn
}

output "webhook_secret" {
  description = "Webhook secret — GitHub App(또는 저장소 웹훅)의 Webhook secret 에 넣는다"
  value       = random_id.webhook.hex
  sensitive   = true
}

output "web_password_parameter" {
  description = "웹 UI Basic 인증 비밀번호가 든 SSM 파라미터 (사용자 이름: var.web_username)"
  value       = aws_ssm_parameter.secret["web/password"].name
}

output "cloudfront_domain_name" {
  description = "atlantis.<도메인> 이 가리키는 CloudFront 배포"
  value       = aws_cloudfront_distribution.atlantis.domain_name
}

output "ecs_task_definition" {
  description = "Task definition for ECS service (used for external triggers)"
  value       = aws_ecs_service.atlantis.task_definition
}
