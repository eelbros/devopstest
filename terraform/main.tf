# terraform/main.tf

# Terraform configuration to provision AWS infrastructure for the ECSFargate service



# Configure the AWS provider

provider "aws" {

  region = var.aws_region

}



# Define variables

variable "aws_region" {

  description = "The AWS region to deploy resources into"

  type        = string

  default     = "us-east-1" # You can change this to your preferred region

}



variable "project_name" {

  description = "A unique name for the project, used for resource naming"

  type        = string

  default     = "zameel-devops-flask"

}



# --- Networking (VPC, Subnets, Internet Gateway, Route Table) ---

resource "aws_vpc" "main" {

  cidr_block = "10.0.0.0/16"

  tags = {

    Name = "${var.project_name}-vpc"

  }

}



resource "aws_internet_gateway" "gw" {

  vpc_id = aws_vpc.main.id

  tags = {

    Name = "${var.project_name}-igw"

  }

}



resource "aws_subnet" "public_a" {

  vpc_id            = aws_vpc.main.id

  cidr_block        = "10.0.1.0/24"

  availability_zone = "${var.aws_region}a"

  map_public_ip_on_launch = true 
# Instances launched in this subnet get a public IP

  tags = {

    Name = "${var.project_name}-public-a"

  }

}



resource "aws_subnet" "public_b" {

  vpc_id            = aws_vpc.main.id

  cidr_block        = "10.0.2.0/24"

  availability_zone = "${var.aws_region}b"

  map_public_ip_on_launch = true

  tags = {

    Name = "${var.project_name}-public-b"

  }

}



resource "aws_route_table" "public" {

  vpc_id = aws_vpc.main.id

  route {

    cidr_block = "0.0.0.0/0"

    gateway_id = aws_internet_gateway.gw.id

  }

  tags = {

    Name = "${var.project_name}-public-rt"

  }

}



resource "aws_route_table_association" "public_a" {

  subnet_id      = aws_subnet.public_a.id

  route_table_id = aws_route_table.public.id

}



resource "aws_route_table_association" "public_b" {

  subnet_id      = aws_subnet.public_b.id

  route_table_id = aws_route_table.public.id

}



# --- Security Group for ALB and ECS Tasks ---

resource "aws_security_group" "alb_sg" {

  vpc_id      = aws_vpc.main.id

  description = "Allow HTTP inbound traffic to ALB"

  name        = "${var.project_name}-alb-sg"



  ingress {

    from_port   = 80

    to_port     = 80

    protocol    = "tcp"

    cidr_blocks = ["0.0.0.0/0"] # Allow HTTP from anywhere

  }

  egress {

    from_port   = 0

    to_port     = 0

    protocol    = "-1" # Allow all outbound traffic

    cidr_blocks = ["0.0.0.0/0"]

  }

  tags = {

    Name = "${var.project_name}-alb-sg"

  }

}



resource "aws_security_group" "ecs_task_sg" {

  vpc_id      = aws_vpc.main.id

  description = "Allow inbound traffic from ALB to ECS tasks"

  name        = "${var.project_name}-ecs-task-sg"



  ingress {

    from_port       = 80

    to_port         = 80

    protocol        = "tcp"

    security_groups = [aws_security_group.alb_sg.id]
 # Only allow traffic from ALB

  }

  egress {

    from_port   = 0

    to_port     = 0

    protocol    = "-1"

    cidr_blocks = ["0.0.0.0/0"]

  }

  tags = {

    Name = "${var.project_name}-ecs-task-sg"

  }

}



# --- Elastic Container Registry (ECR) ---

resource "aws_ecr_repository" "app_repo" {

  name                 = "${var.project_name}-repo"

  image_tag_mutability = "MUTABLE"
 # Allows overwriting image tags

  image_scanning_configuration {

    scan_on_push = true

  }

  tags = {

    Name = "${var.project_name}-repo"

  }

}



# --- ECS Cluster ---

resource "aws_ecs_cluster" "main" {

  name = "${var.project_name}-cluster"

  tags = {

    Name = "${var.project_name}-cluster"

  }

}



# --- ECS Task Definition (Fargate) ---

resource "aws_iam_role" "ecs_task_execution_role" {

  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {

        Action = "sts:AssumeRole"

        Effect = "Allow"

        Principal = {

          Service = "ecs-tasks.amazonaws.com"

        }

      },

    ]

  })

  tags = {

    Name = "${var.project_name}-ecs-task-execution-role"

  }

}



resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {

  role       = aws_iam_role.ecs_task_execution_role.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"

}



resource "aws_ecs_task_definition" "app_task" {

  family                   = "${var.project_name}-task"

  cpu                      = "256" # 0.25 vCPU

  memory                   = "512" # 0.5 GB

  network_mode             = "awsvpc"

  requires_compatibilities = ["FARGATE"]

  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([

    {

      name        = var.project_name

      image       = "${aws_ecr_repository.app_repo.repository_url}:latest"
 #Placeholder, updated by CI/CD

      cpu         = 256

      memory      = 512

      essential   = true

      portMappings = [

        {

          containerPort = 80

          hostPort      = 80

          protocol      = "tcp"

        }

      ]

      logConfiguration = {

        logDriver = "awslogs"

        options = {

          "awslogs-group"         = "/ecs/${var.project_name}"

          "awslogs-region"        = var.aws_region

          "awslogs-stream-prefix" = "ecs"

        }

      }

    }

  ])

  tags = {

    Name = "${var.project_name}-task-definition"

  }

}



# --- CloudWatch Log Group for ECS Task Logs ---

resource "aws_cloudwatch_log_group" "ecs_logs" {

  name              = "/ecs/${var.project_name}"

  retention_in_days = 7 # Adjust as needed

  tags = {

    Name = "${var.project_name}-ecs-log-group"

  }

}



# --- ECS Service ---

resource "aws_ecs_service" "app_service" {

  name            = "${var.project_name}-service"

  cluster         = aws_ecs_cluster.main.id

  task_definition = aws_ecs_task_definition.app_task.arn

  desired_count   = 1 # Number of running tasks

  launch_type     = "FARGATE"



  network_configuration {

    subnets         = [aws_subnet.public_a.id, aws_subnet.public_b.id]

    security_groups = [aws_security_group.ecs_task_sg.id]

    assign_public_ip = true

  }



  load_balancer {

    target_group_arn = aws_lb_target_group.app_tg.arn

    container_name   = var.project_name

    container_port   = 80

  }

  tags = {

    Name = "${var.project_name}-ecs-service"

  }

}



# --- Application Load Balancer (ALB) ---

resource "aws_lb" "app_lb" {

  name               = "${var.project_name}-lb"

  internal           = false

  load_balancer_type = "application"

  security_groups    = [aws_security_group.alb_sg.id]

  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = {

    Name = "${var.project_name}-alb"

  }

}



resource "aws_lb_target_group" "app_tg" {

  name        = "${var.project_name}-tg"

  port        = 80

  protocol    = "HTTP"

  vpc_id      = aws_vpc.main.id

  target_type = "ip" # Required for Fargate

  tags = {

    Name = "${var.project_name}-tg"

  }

}



resource "aws_lb_listener" "http_listener" {

  load_balancer_arn = aws_lb.app_lb.arn

  port              = 80

  protocol          = "HTTP"



  default_action {

    type             = "forward"

    target_group_arn = aws_lb_target_group.app_tg.arn

  }

  tags = {

    Name = "${var.project_name}-http-listener"

  }

}



# --- Outputs ---

output "alb_dns_name" {

  description = "The DNS name of the Application Load Balancer"

  value       = aws_lb.app_lb.dns_name

}



output "ecr_repository_url" {

  description = "The URL of the ECR repository"

  value       = aws_ecr_repository.app_repo.repository_url

}



output "ecs_cluster_name" {

  description = "The name of the ECS cluster"

  value       = aws_ecs_cluster.main.name

}



output "ecs_service_name" {

  description = "The name of the ECS service"

  value       = aws_ecs_service.app_service.name
}
