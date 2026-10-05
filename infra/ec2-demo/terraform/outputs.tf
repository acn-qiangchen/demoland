output "instance_id" {
  description = "EC2 instance ID (use as the --target for SSM Session Manager)."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "Public IPv4 address of the instance."
  value       = aws_instance.this.public_ip
}

output "public_dns" {
  description = "Public DNS name of the instance."
  value       = aws_instance.this.public_dns
}

output "ssh_command" {
  description = "SSH in with the private key matching the hardcoded public key."
  value       = "ssh ec2-user@${aws_instance.this.public_ip}"
}

output "ssm_command" {
  description = "Open a shell via SSM Session Manager (no inbound port, no key needed)."
  value       = "aws ssm start-session --target ${aws_instance.this.id}"
}
