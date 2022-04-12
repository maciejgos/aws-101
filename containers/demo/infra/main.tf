terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.8.0"
    }
  }
}

provider "aws" {
  # Configuration options
  region = "eu-central-1"
}

variable "vpc_id" {
  type    = string
  default = "vpc-0fead40e24304ce5f"
}

variable "subnet_id" {
  type    = string
  default = "subnet-0c5ab4a1499db9f85"
}

variable "user_prefix" {
  type    = string
  default = "mg"
}

data "aws_vpc" "vpc" {
  id = var.vpc_id
}

data "aws_subnet" "snet" {
  id = var.subnet_id
}

resource "aws_ecr_repository" "ecr" {
  name = "${var.user_prefix}-repository"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "${var.user_prefix}-execution-task-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_ecs_cluster" "ecs" {
  name = "${var.user_prefix}-cluster"
}

resource "aws_security_group" "ecs_sg" {
  vpc_id = data.aws_vpc.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_iam_policy_document" "ecs_agent" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_agent" {
  name               = "${var.user_prefix}-ecs-agent"
  assume_role_policy = data.aws_iam_policy_document.ecs_agent.json
}

resource "aws_iam_role_policy_attachment" "ecs_agent" {
  role       = aws_iam_role.ecs_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_agent" {
  name = "${var.user_prefix}-ecs-agent"
  role = aws_iam_role.ecs_agent.name
}

resource "aws_launch_configuration" "ecs_launch_config" {
  image_id                    = "ami-0c114f68881dc4f44"
  iam_instance_profile        = aws_iam_instance_profile.ecs_agent.name
  security_groups             = [aws_security_group.ecs_sg.id]
  user_data                   = "#!/bin/bash\n echo ECS_CLUSTER=${aws_ecs_cluster.ecs.name} >> /etc/ecs/ecs.config"
  instance_type               = "t2.micro"
  associate_public_ip_address = true
}

resource "aws_autoscaling_group" "asg" {
  name                 = "asg"
  vpc_zone_identifier  = [data.aws_subnet.snet.id]
  launch_configuration = aws_launch_configuration.ecs_launch_config.name

  desired_capacity          = 1
  min_size                  = 1
  max_size                  = 10
  health_check_grace_period = 300
  health_check_type         = "EC2"
}

resource "aws_ecs_task_definition" "service" {
  family             = "${var.user_prefix}-definition"
  cpu                = "1vcpu"
  memory             = "512"
  execution_role_arn = aws_iam_role.ecsTaskExecutionRole.arn
  task_role_arn      = aws_iam_role.ecsTaskExecutionRole.arn

  container_definitions = jsonencode([
    {
      name      = "hello-world-container"
      image     = "${aws_ecr_repository.ecr.repository_url}:latest"
      cpu       = 1
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "service" {
  name                    = "${var.user_prefix}-service"
  cluster                 = aws_ecs_cluster.ecs.id
  task_definition         = aws_ecs_task_definition.service.arn
  desired_count           = 1
  enable_ecs_managed_tags = true
  launch_type             = "EC2"
}
