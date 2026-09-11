output "public_ip" {
  description = "Public IP of the three-tier server"
  value       = aws_instance.three_tier.public_ip
}

output "frontend_url" {
  description = "URL to open the app (frontend on port 3000)"
  value       = format("http://%s:3000", aws_instance.three_tier.public_ip)
}

output "ssh_command" {
  description = "Command to SSH into the server"
  value       = format("ssh -i your-key.pem ec2-user@%s", aws_instance.three_tier.public_ip)
}