terraform {
  backend "s3" {
    bucket = "caisarus"
    key    = "terraform/terraform.tfstate"
    region = "eu-west-3"
  }
}

provider "aws" {
  region = var.aws_region
}

# Fetch all availability zones in the region
data "aws_availability_zones" "available" {}

resource "aws_iam_role" "ssm_role" {
  name = "ssm_role_unique"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "s3_read_policy_attachment" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_instance_profile.name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              {
              sudo yum update -y
              sudo yum install -y python3 aws-cli
              sudo pip3 install flask waitress

              # Download the phonebook.py file from S3
              aws s3 cp s3://${var.bucket_name}/phonebook.py /home/ec2-user/phonebook.py

              if [ -f /home/ec2-user/phonebook.py ]; then
                echo "phonebook.py downloaded successfully"
              else
                echo "Failed to download phonebook.py" >&2
                exit 1
              fi

              # Create the phonebook.service file
              echo '[Unit]
              Description=Waitress instance to serve phonebook
              After=network.target

              [Service]
              WorkingDirectory=/home/ec2-user
              Environment="PATH=/home/ec2-user/.local/bin"
              ExecStart=/usr/bin/python3 /home/ec2-user/phonebook.py
              StandardOutput=file:/var/log/waitress/output.log
              StandardError=file:/var/log/waitress/error.log

              [Install]
              WantedBy=multi-user.target' | sudo tee /etc/systemd/system/phonebook.service

              sudo mkdir -p /var/log/waitress
              sudo touch /var/log/waitress/output.log /var/log/waitress/error.log
              sudo chown ec2-user:ec2-user /var/log/waitress/*

              # Reload systemd manager configuration
              sudo systemctl daemon-reload

              # Start and enable the phonebook service
              sudo systemctl start phonebook
              sudo systemctl enable phonebook

              # Output the status of the phonebook service for debugging
              sudo systemctl status phonebook
              } 2>&1 | tee /home/ec2-user/userdata.log
              EOF

  tags = {
    Name = "PhonebookAppInstance"
  }
}

resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "ssm_instance_profile_unique"
  role = aws_iam_role.ssm_role.name
}

resource "aws_security_group" "lb" {
  vpc_id = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2" {
  vpc_id = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elb" "app" {
  name               = "phonebook-app-lb"
  availability_zones = data.aws_availability_zones.available.names

  listener {
    instance_port     = 5000
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  health_check {
    target              = "HTTP:5000/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  instances = [aws_instance.app.id]

  security_groups = [aws_security_group.lb.id]

  tags = {
    Name = "PhonebookAppLoadBalancer"
  }
}

resource "aws_route53_record" "www" {
  zone_id = var.route53_zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_elb.app.dns_name]
}

resource "aws_route53_record" "root" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_elb.app.dns_name
    zone_id                = aws_elb.app.zone_id
    evaluate_target_health = false
  }
}

output "elb_dns_name" {
  value       = aws_elb.app.dns_name
  description = "The DNS name of the load balancer"
}

output "route53_record_name" {
  value       = aws_route53_record.root.fqdn
  description = "The FQDN of the Route 53 record to access the application"
}
