# terraform/aws/variables.tf

variable "aws_region" {
  default = "us-east-1"
}

variable "environment" {
  default = "prod"
}

variable "mysql_password" {
  type      = string
  sensitive = true
}
