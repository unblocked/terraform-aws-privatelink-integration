output "endpoint_service_name" {
  description = "Endpoint service name to give Unblocked."
  value       = aws_vpc_endpoint_service.this.service_name
}

output "owner_account_id" {
  description = "AWS account ID that owns the endpoint service, to give Unblocked."
  value       = data.aws_caller_identity.current.account_id
}

output "endpoint_service_id" {
  description = "Endpoint service ID, for accepting or rejecting connections."
  value       = aws_vpc_endpoint_service.this.id
}

output "port" {
  description = "Port the endpoint service exposes."
  value       = var.port
}

output "nlb_security_group_id" {
  description = "Security group of the NLB. Allow it on the port in the database's security group, unless database_security_group_id is set."
  value       = aws_security_group.nlb.id
}

output "target_group_arn" {
  description = "ARN of the target group. Register and maintain the database IPs in it outside Terraform."
  value       = aws_lb_target_group.this.arn
}

output "nlb_arn" {
  description = "ARN of the NLB behind the endpoint service."
  value       = aws_lb.this.arn
}
