provider "aws" {
  region = "eu-west-3" # Change this to your desired region
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "main" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
}

data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "a" {
  count          = 2
  subnet_id      = element(aws_subnet.main.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_ecs_cluster" "main" {
  name = "phonebook-app-cluster"
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "phonebook_app" {
  family                   = "phonebook-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  cpu                      = 256
  memory                   = 512

  container_definitions = jsonencode([{
    name      = "phonebook-app"
    image     = "886156520844.dkr.ecr.eu-west-3.amazonaws.com/phonebook-app:v5"
    essential = true
    portMappings = [{
      containerPort = 5000
      hostPort      = 5000
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/phonebook-app"
        "awslogs-region"        = "eu-west-3"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/phonebook-app"
  retention_in_days = 7
}



resource "aws_ecs_service" "phonebook_app" {
  name            = "phonebook-app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.phonebook_app.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    assign_public_ip = true # Ensure the task gets a public IP
    subnets          = aws_subnet.main[*].id
    security_groups  = [aws_security_group.ecs_service.id]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "phonebook-app"
    container_port   = 5000
  }
}

resource "aws_security_group" "ecs_service" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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


resource "aws_lb" "main" {
  name               = "phonebook-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_service.id]
  subnets            = aws_subnet.main[*].id
}

resource "aws_lb_target_group" "main" {
  name        = "phonebook-app-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

resource "aws_route53_zone" "main" {
  name = "caisarus.net"
}

resource "aws_route53_record" "main" {
  zone_id = "Z0937771WKWN0S65XX8S"
  name    = "fargate.caisarus.net"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
