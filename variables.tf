variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "domain_name" {
  description = "Route53 で管理するドメイン名"
  type        = string
}

variable "aws_vpc_id" {
  description = "aws vpc id"
  type        = string
}

variable "client_public_ip" {
  description = "Client EC2 のパブリックIP"
  type        = string
}

variable "server_private_ip" {
  description = "Server EC2 のプライベートIP"
  type        = string
}

variable "host_zone_id" {
  description = "Route53 Hostzone ID"
  type        = string
}
