provider "aws" {
  region = var.aws_region
}

locals {
    project_name = "${var.environment}-${var.project}"
    tags = {
      Name        = local.project_name
      Environment = var.environment
      Project     = var.project
      ManagedBy    = "Terraform"
    }
    vpc_cidr = "10.0.0.0/16"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = local.tags
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_cidr
  availability_zone = var.availability_zone
  tags = local.tags
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = local.tags
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = local.tags
}

resource "aws_route_table_association" "main" {
  subnet_id = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_instance" "app" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  subnet_id = aws_subnet.public.id
  tags = local.tags
}

resource "aws_security_group" "app_sg" {
  name        = "${local.project_name}-sg"
  description = "Security group for devops-app"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow app traffic on port 5000"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
  }