# SSM Session Manager access for the instance. The AWS-managed AmazonSSMManagedInstanceCore
# policy grants exactly what the SSM agent needs to register and open sessions.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm" {
  name               = "${var.app_name}-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Name = "${var.app_name}-ssm-role" }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.app_name}-ssm-profile"
  role = aws_iam_role.ssm.name

  tags = { Name = "${var.app_name}-ssm-profile" }
}
