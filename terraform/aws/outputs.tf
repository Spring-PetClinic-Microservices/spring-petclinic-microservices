# terraform/aws/outputs.tf

output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "ecr_registry_url" {
  description = "ECR registry base URL"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "rds_endpoint" {
  value = aws_db_instance.main.endpoint
}
