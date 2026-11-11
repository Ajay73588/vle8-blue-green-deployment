output "instance_id" {
  description = "EC2 Instance ID for VLE-8 server."
  value       = aws_instance.vle8_server.id
}

output "public_ip" {
  description = "Public IPv4 address of the VLE-8 EC2 instance."
  value       = aws_instance.vle8_server.public_ip
}

output "public_dns" {
  description = "Public DNS hostname of the VLE-8 EC2 instance."
  value       = aws_instance.vle8_server.public_dns
}

output "ami_id" {
  description = "Resolved Ubuntu 24.04 LTS AMI ID in ap-south-1."
  value       = data.aws_ami.ubuntu.id
}

output "ami_name" {
  description = "Resolved Ubuntu 24.04 LTS AMI Name."
  value       = data.aws_ami.ubuntu.name
}

output "availability_zone" {
  description = "Availability zone where the EC2 instance is launched."
  value       = aws_instance.vle8_server.availability_zone
}

output "security_group_id" {
  description = "ID of the VLE-8 security group."
  value       = aws_security_group.vle8.id
}

output "ssm_start_session_command" {
  description = "AWS SSM Session Manager command to open an interactive shell over HTTPS 443."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.vle8_server.id}"
}

output "ssm_port_forward_jenkins_command" {
  description = "Fallback AWS SSM port-forward command if direct port 8080 access is ever blocked."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.vle8_server.id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"8080\"],\"localPortNumber\":[\"8080\"]}'"
}

output "ssm_port_forward_app_command" {
  description = "Fallback AWS SSM port-forward command if direct port 80 access is ever blocked."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.vle8_server.id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"80\"],\"localPortNumber\":[\"8081\"]}'"
}

output "jenkins_url" {
  description = "Jenkins Web UI URL."
  value       = "http://${aws_instance.vle8_server.public_ip}:8080"
}

output "app_url" {
  description = "Blue-Green Demo Application URL."
  value       = "http://${aws_instance.vle8_server.public_ip}"
}

