terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  project = "demo-dns01"
  common_tags = {
    Project = local.project
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

############################
# Route53 Hosted Zone
############################

resource "aws_route53_zone" "demo-dns01-zone" {
  name    = var.domain_name
  comment = "Hosted zone for ${local.project}"
  vpc {
    vpc_id = var.aws_vpc_id
  }
  tags = {
    Name = "demo-dns01-zone"
  }
}

############################
# A Records
############################

# Vault Agent (EC2-00) の公開IPを指すAレコード
resource "aws_route53_record" "client" {
  zone_id = aws_route53_zone.demo-dns01-zone.zone_id
  name    = "client.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [var.client_public_ip]
}
/*
# Vault Server (EC2-01) のプライベートIPを指すAレコード
resource "aws_route53_record" "server" {
  zone_id = aws_route53_zone.demo-dns01-zone.zone_id
  name    = "vault.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [var.server_private_ip]
}
*/
