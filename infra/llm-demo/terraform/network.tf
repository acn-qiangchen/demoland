data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Two public subnets in two AZs (ALB requires >= 2 AZs).
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.app_name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.app_name}-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.app_name}-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.app_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---- Security groups ----

# ALB: ingress on 80 open to the internet. API Gateway's integration egress has no stable
# prefix list to scope to, so the X-Origin-Verify listener rule (not the SG) is the real
# access control — direct hits without the secret header get a 403 from the default action.
resource "aws_security_group" "alb" {
  name        = "${var.app_name}-alb-sg"
  description = "ALB ingress on 80 (access gated by X-Origin-Verify listener rule)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from anywhere (secret header enforced at listener rule)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-alb-sg" }
}

# ECS tasks: ingress on the bff port (8081) only from the ALB SG.
# The backend's 8080 needs no rule — same-task container-to-container traffic uses
# loopback and is not filtered by security groups.
resource "aws_security_group" "ecs" {
  name        = "${var.app_name}-ecs-sg"
  description = "ECS task ingress from ALB only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "BFF port from ALB"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-ecs-sg" }
}
