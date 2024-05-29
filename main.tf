provider "aws" {
  region = "eu-west-3"
}

resource "aws_iam_role" "ssm_role" {
  name = "ssm_role"

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
  ami                    = "ami-0fc25b16af4d1f440"
  instance_type          = "t3.micro"
  subnet_id              = "subnet-0a82ef2b1796a3915"
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_instance_profile.name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y python3 aws-cli
              sudo pip3 install flask waitress

              # Download the phonebook.py file from S3
              aws s3 cp s3://caisarus/phonebook.py /home/ec2-user/phonebook.py

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

              [Install]
              WantedBy=multi-user.target' | sudo tee /etc/systemd/system/phonebook.service

              # Start and enable the phonebook service
              sudo systemctl enable phonebook.service
              sudo systemctl start phonebook.service
              EOF
}


resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "ssm_instance_profile_${random_string.suffix.result}"
  role = aws_iam_role.ssm_role.name
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}


resource "aws_security_group" "lb" {
  vpc_id = "vpc-039f9bfc699f4d04b"

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
  vpc_id = "vpc-039f9bfc699f4d04b"

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
  availability_zones = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]

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
  zone_id = "Z0937771WKWN0S65XX8S"
  name    = "www.ec2.caisarus.net"
  type    = "CNAME"
  ttl     = 300
  records = [aws_elb.app.dns_name]
}

resource "aws_route53_record" "root" {
  zone_id = "Z0937771WKWN0S65XX8S"
  name    = "ec2.caisarus.net"
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

