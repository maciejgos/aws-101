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
  type = string
}

variable "user_prefix" {
  type    = string
  default = "mg"
}

data "aws_vpc" "vpc" {
  id = var.vpc_id
}

resource "aws_ecr_repository" "ecr" {
  name = "${var.user_prefix}-repository"
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "${var.user_prefix}-execution-task-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
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

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_ecs_cluster" "ecs" {
  name = "${var.user_prefix}-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "ecs" {
  cluster_name = aws_ecs_cluster.ecs.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 10
    capacity_provider = "FARGATE"
  }
}

resource "aws_ecs_task_definition" "service" {
  family                   = "${var.user_prefix}-definition"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 10
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn
  task_role_arn            = aws_iam_role.ecsTaskExecutionRole.arn

  container_definitions = <<DEFINITION
  [
    {
      "name": "hello-world-container",
      "image": "${aws_ecr_repository.ecr.repository_url}/${var.user_prefix}-repository:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 80,
          "hostPort": 80
        }
      ],
      "cpu": 10,
      "memory": 512,
      "networkMode": "awsvpc"
    }
  ]
  DEFINITION
}

resource "aws_ecs_service" "service" {
  name            = "${var.user_prefix}-service"
  cluster         = aws_ecs_cluster.ecs.id
  task_definition = aws_ecs_task_definition.service.arn
  desired_count   = 1
  launch_type     = "FARGATE"
}
