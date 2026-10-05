variable "app_name" {
  description = "Logical name of the demo app; used as a prefix for all resource names."
  type        = string
  default     = "ec2-demo"
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to reach the instance over SSH (TCP 22). Defaults to the whole internet for demo convenience — narrow this to your own IP for real use."
  type        = string
  default     = "0.0.0.0/0"
}
