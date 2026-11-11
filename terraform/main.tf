# Dynamically discover the latest official Canonical Ubuntu 24.04 LTS AMI in ap-south-1
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Use existing AWS Default VPC and public subnet to avoid unnecessary VPC/NAT Gateway costs
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "availability-zone"
    values = [var.availability_zone]
  }
}

# Dedicated IAM Role & Instance Profile for AWS SSM Session Manager (HTTPS-based remote access without port 22)
resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

# Fresh SSH Key Pair used for SSH-over-SSM ProxyCommand authentication
resource "aws_key_pair" "vle8" {
  key_name   = "${var.project_name}-key"
  public_key = trimspace(file(var.ssh_public_key_path))
}

# Security Group exposing only necessary application & Jenkins ports (no 0.0.0.0/0 SSH)
resource "aws_security_group" "vle8" {
  name        = "${var.project_name}-sg"
  description = "Security group for VLE-8 Blue-Green Jenkins + Kubernetes host"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "${var.project_name}-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_http" {
  for_each = toset(var.allowed_app_cidrs)

  security_group_id = aws_security_group.vle8.id
  description       = "Allow HTTP (port 80) to demo application from allowed CIDR"
  cidr_ipv4         = each.value
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_http" {
  for_each = toset(concat(
    var.allowed_admin_cidrs,
    var.enable_github_webhook_ingress ? var.github_webhook_cidrs : []
  ))

  security_group_id = aws_security_group.vle8.id
  description       = contains(var.allowed_admin_cidrs, each.value) ? "Allow Jenkins UI (port 8080) from admin CIDR" : "Allow GitHub Webhook delivery to Jenkins (port 8080)"
  cidr_ipv4         = each.value
  from_port         = 8080
  ip_protocol       = "tcp"
  to_port           = 8080
}

resource "aws_vpc_security_group_ingress_rule" "ssh_optional" {
  for_each = var.allow_ssh_ingress ? toset(var.allowed_admin_cidrs) : toset([])

  security_group_id = aws_security_group.vle8.id
  description       = "Optional SSH (port 22) restricted to admin CIDR"
  cidr_ipv4         = each.value
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.vle8.id
  description       = "Allow all outbound IPv4 traffic for package repos, Docker Hub, GitHub, and AWS SSM"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# EC2 Instance for Jenkins, Docker, kubectl, and Minikube
resource "aws_instance" "vle8_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = sort(data.aws_subnets.default.ids)[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.vle8.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm_profile.name
  key_name                    = aws_key_pair.vle8.key_name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Enforce IMDSv2
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              set -euxo pipefail
              hostnamectl set-hostname vle8-blue-green
              if ! snap list amazon-ssm-agent >/dev/null 2>&1; then
                snap install amazon-ssm-agent --classic
              fi
              systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service
              EOF

  tags = {
    Name = "${var.project_name}-server"
  }
}

