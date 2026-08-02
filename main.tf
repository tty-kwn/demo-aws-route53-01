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

# VPC
resource "aws_vpc" "base01-vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "base01-vpc"
  }
}

# IGW
resource "aws_internet_gateway" "base01-igw" {
  vpc_id = aws_vpc.base01-vpc.id

  tags = {
    Name = "base01-igw"
  }
}

# Subnet（Public）- AZ a
resource "aws_subnet" "base01-public-subnet01" {
  vpc_id                  = aws_vpc.base01-vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "base01-public-subnet01"
  }
}

# Subnet（Private）- AZ a
resource "aws_subnet" "base01-private-subnet02" {
  vpc_id            = aws_vpc.base01-vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "base01-private-subnet02"
  }
}

# Subnet（Private）- AZ c
resource "aws_subnet" "base01-private-subnet03" {
  vpc_id            = aws_vpc.base01-vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-northeast-1c"

  tags = {
    Name = "base01-private-subnet03"
  }
}

# Public RT（IGWへデフォルトルート）
resource "aws_route_table" "base01-public-rt" {
  vpc_id = aws_vpc.base01-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.base01-igw.id
  }

  /*
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.igw.id
  }
  */

  tags = {
    Name = "base01-public-rt"
  }
}


resource "aws_route_table" "base01-private-rt02" {
  vpc_id = aws_vpc.base01-vpc.id

  tags = {
    Name = "base01-private-rt02"
  }
}

resource "aws_route" "base01-private-default-rt02" {
  route_table_id         = aws_route_table.base01-private-rt02.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.base01-ngw-01.id
}

resource "aws_route_table" "base01-private-rt03" {
  vpc_id = aws_vpc.base01-vpc.id

  tags = {
    Name = "base01-private-rt03"
  }
}

resource "aws_route" "base01-private-default-rt03" {
  route_table_id         = aws_route_table.base01-private-rt03.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.base01-ngw-01.id
}

resource "aws_route_table_association" "base01-public-association01" {
  route_table_id = aws_route_table.base01-public-rt.id
  subnet_id      = aws_subnet.base01-public-subnet01.id
}

resource "aws_route_table_association" "base01-private_association03" {
  subnet_id      = aws_subnet.base01-private-subnet03.id
  route_table_id = aws_route_table.base01-private-rt03.id
}

resource "aws_route_table_association" "base01-private_association02" {
  subnet_id      = aws_subnet.base01-private-subnet02.id
  route_table_id = aws_route_table.base01-private-rt02.id
}

resource "aws_eip" "base01-eip" {
  domain = "vpc"

  tags = {
    Name = "nat-eip"
  }
}

resource "aws_nat_gateway" "base01-ngw-01" {
  allocation_id = aws_eip.base01-eip.id
  subnet_id     = aws_subnet.base01-public-subnet01.id
  tags = {
    Name = "nat-gw"
  }
  depends_on = [aws_internet_gateway.base01-igw]
}

############################
# Security Groups
############################

# EC2 用 SG：SSH(22)を許可（from allowed_ssh_cidr）、アウトバウンドは全許可
resource "aws_security_group" "base01-ec2-sg" {
  name        = "base01-ec2-sg"
  description = "EC2 security group"
  vpc_id      = aws_vpc.base01-vpc.id

  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "Vault from allowed CIDR"
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = [var.allowed_vault_cidr]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "base01-ec2-sg"
  }
}


############################
# EC2 Instances 
############################

resource "aws_instance" "base01-ec2-00" {
  #  ami                         = data.aws_ami.vd1-AmazonLinux-ami.id
  # プライベートイメージのフィルターでhc-base-al2023-x86_64
  ami                         = var.ec2_ami_id
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.base01-public-subnet01.id
  vpc_security_group_ids      = [aws_security_group.base01-ec2-sg.id]
  key_name                    = var.ec2_key_name
  associate_public_ip_address = true

  tags = {
    Name = "base01-ec2-00"
    Role = "Bastion Host"
  }
}

resource "aws_instance" "base01-ec2-01" {
  #  ami                         = data.aws_ami.vd1-AmazonLinux-ami.id
  ami                         = var.ec2_ami_id
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.base01-private-subnet02.id
  vpc_security_group_ids      = [aws_security_group.base01-ec2-sg.id]
  key_name                    = var.ec2_key_name
  associate_public_ip_address = false

  tags = {
    Name = "base01-ec2-01"
    Role = "EC2 Instance 01"
  }
}

############################
# Route53 Hosted Zone
############################

resource "aws_route53_zone" "demo-dns01-zone" {
  name    = var.domain_name
  comment = "Hosted zone for ${local.project}"
  vpc {
    vpc_id = aws_vpc.base01-vpc.id
  }
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
  records = [aws_instance.base01-ec2-00.public_ip]
}

# Server (EC2-01) のプライベートIPを指すAレコード
resource "aws_route53_record" "server" {
  zone_id = aws_route53_zone.demo-dns01-zone.zone_id
  name    = "server.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.base01-ec2-01.private_ip]
}

