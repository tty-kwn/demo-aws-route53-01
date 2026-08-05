variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}
variable "allowed_ssh_cidr" {
  description = "CIDR allowed to access EC2 via SSH"
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_vault_cidr" {
  description = "CIDR allowed to access Vault API"
  type        = string
  default     = "10.0.0.0/16"
}

variable "domain_name" {
  description = "Route53 で管理するドメイン名"
  type        = string
}
