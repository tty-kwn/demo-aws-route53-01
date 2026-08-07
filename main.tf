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
  project = "base01"
  common_tags = {
    Project = local.project
  }
}

provider "aws" {
  region = var.aws_region # 東京リージョン

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
  tags = {
    Name = "demo-dns01-zone"
  }
}

############################
# A Records
############################

# Client (EC2-00) の公開IPを指すAレコード
resource "aws_route53_record" "client" {
  zone_id = aws_route53_zone.demo-dns01-zone.zone_id
  name    = "client.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = ["10.0.0.1"]
}
/*
# Server (EC2-01) のプライベートIPを指すAレコード
resource "aws_route53_record" "server" {
  zone_id = aws_route53_zone.demo-dns01-zone.zone_id
  name    = "server.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.base01-ec2-01.private_ip]
}
*/



resource "aws_route53_record" "server" {
  zone_id = aws_route53_zone.demo-dns01-zone.zone_id
  name    = "client2.demo.home"
  type    = "A"
  ttl     = 300
  records = ["10.0.0.2"]
}


resource "aws_route53_record" "client3_demo_home" {
  zone_id = aws_route53_zone.demo-dns01-zone.zone_id
  name    = "client3.demo.home"
  type    = "A"
  ttl     = 300
  records = ["10.0.0.3"]
}


resource "aws_route53_record" "client4_demo_home" {
  zone_id = aws_route53_zone.demo-dns01-zone.zone_id
  name    = "client4.demo.home"
  type    = "A"
  ttl     = 300
  records = ["10.0.0.4"]
}


resource "aws_route53_record" "client5_demo_home" {
  zone_id = aws_route53_zone.demo-dns01-zone.zone_id
  name    = "client5.demo.home"
  type    = "A"
  ttl     = 300
  records = ["10.0.0.5"]
}


resource "aws_route53_record" "client6_demo_home" {
  zone_id = aws_route53_zone.demo-dns01-zone.zone_id
  name    = "client6.demo.home"
  type    = "A"
  ttl     = 300
  records = ["10.0.0.6"]
}