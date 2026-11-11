variable "aws_region" {
  description = "AWS region to provision VLE-8 infrastructure (assignment specifies ap-south-1 Mumbai)."
  type        = string
  default     = "ap-south-1"
}

variable "availability_zone" {
  description = "Preferred availability zone in ap-south-1."
  type        = string
  default     = "ap-south-1a"
}

variable "environment" {
  description = "Deployment environment tag."
  type        = string
  default     = "vle8-lab"
}

variable "project_name" {
  description = "Prefix used for AWS resource names."
  type        = string
  default     = "vle8-blue-green"
}

variable "instance_type" {
  description = "EC2 instance type sized for Jenkins + Docker + Minikube (2 vCPU, 4 GiB RAM, Free-Tier eligible on AWS Free Plan)."
  type        = string
  default     = "c7i-flex.large"
}

variable "root_volume_size" {
  description = "Root EBS gp3 volume size in GiB."
  type        = number
  default     = 30
}

variable "ssh_public_key_path" {
  description = "Path to the fresh ED25519 public key generated for this VLE-8 project."
  type        = string
  default     = "../.keys/vle8-ed25519.pub"
}

variable "allowed_admin_cidrs" {
  description = "CIDR blocks permitted to access Jenkins (port 8080) and optional SSH. Restrict to your current public IP (/32)."
  type        = list(string)
}

variable "allowed_app_cidrs" {
  description = "CIDR blocks permitted to access the demo web application (port 80). Restrict to your current public IP (/32) or presentation network."
  type        = list(string)
}

variable "enable_github_webhook_ingress" {
  description = "Allow GitHub official webhook IPv4 CIDR ranges to reach Jenkins on port 8080."
  type        = bool
  default     = true
}

variable "github_webhook_cidrs" {
  description = "Official GitHub webhook source IPv4 CIDRs from https://api.github.com/meta (.hooks)."
  type        = list(string)
  default = [
    "9.234.106.48/28",
    "9.234.98.160/28",
    "9.234.98.176/28",
    "192.30.252.0/22",
    "185.199.108.0/22",
    "140.82.112.0/20",
    "143.55.64.0/20"
  ]
}

variable "allow_ssh_ingress" {
  description = "Optional toggle to allow port 22 from allowed_admin_cidrs. Keep false when using AWS SSM Session Manager."
  type        = bool
  default     = false
}

