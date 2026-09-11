variable "region" {
  description = "AWS region to deploy in"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance size (t2.micro is free tier)"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Name of an existing AWS EC2 key pair for SSH access"
  type        = string
}

variable "app_repo" {
  description = "GitHub repo the server clones and runs with docker compose"
  type        = string
  default     = "https://github.com/ArlagaddaHepseeba-git/three-tier-application.git"
}