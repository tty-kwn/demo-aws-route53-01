variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "domain_name" {
  description = "Route53 で管理するドメイン名"
  type        = string
}

variable "vault_client_public_ip" {
  description = "Vault Client EC2 のパブリックIP"
  type        = string
}

variable "vault_server_private_ip" {
  description = "Vault Server EC2 のプライベートIP"
  type        = string
}
