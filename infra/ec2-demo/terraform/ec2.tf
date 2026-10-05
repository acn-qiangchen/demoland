# Latest Amazon Linux 2023 AMI (x86_64) from the SSM public parameter. AL2023 ships the
# SSM agent preinstalled, so Session Manager works out of the box once the instance has the
# SSM instance profile and egress to the SSM endpoints.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.this.id]
  key_name                    = aws_key_pair.this.key_name
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
  associate_public_ip_address = true

  tags = { Name = var.app_name }
}
