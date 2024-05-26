variable "aws_region" {
  description = "The AWS region to deploy to"
  default     = "eu-west-3"
}

variable "subnet_id" {
  description = "The subnet ID for the instances"
  default     = "subnet-0a82ef2b1796a3915"
}

variable "vpc_id" {
  description = "The VPC ID for the instances"
  default     = "vpc-039f9bfc699f4d04b"
}

variable "ami_id" {
  description = "The AMI ID for the EC2 instances"
  default     = "ami-0fc25b16af4d1f440"
}

variable "bucket_name" {
  description = "The S3 bucket name for the phonebook.py script"
  default     = "caisarus"
}

variable "route53_zone_id" {
  description = "The Route 53 Hosted Zone ID"
  default     = "Z0937771WKWN0S65XX8S"
}

variable "domain_name" {
  description = "The domain name for the Route 53 record"
  default     = "caisarus.net"
}
