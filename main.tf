

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
data "aws_caller_identity" "current" {}

#Variables
variable "github_repo" {
  description = "The name of the GitHub repository (e.g., app-ecs)"
  type        = string
}

variable "github_branch" {
  description = "The branch to pull the source code from"
  type        = string
  default     = "main"
}

variable "github_oauth_token" {
  description = "GitHub OAuth token used for authenticating with the repository"
  type        = string
  sensitive   = true
}



# NETWORKING

# This networkingprovisions the network infrastructure required for secure and scalable workloads.
# Included components:
#  VPC with customizable CIDR block
#  Public and private subnets across multiple availability zones
#  Internet Gateway for public subnet access
#  NAT Gateway for outbound access from private subnets
#  Route tables and subnet associations for both public and private routing
#  Security groups for ALB and ECS task networking
#  Application Load Balancer (ALB) with listener and target group configuration

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "lampteymain"
  }
}

# Public Subnets
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "publicSubnet1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "publicSubnet2"
  }
}

# Private Subnets
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.1.3.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "privateSubnet1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.1.4.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "privateSubnet2"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "InternetGateway"
  }
}

# EIP for NAT
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

# NAT Gateway
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id

  tags = {
    Name = "NatGateway"
  }
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "PublicRouteTable"
  }
}

# Associate public subnets with route table
resource "aws_route_table_association" "public_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2_assoc" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

# Private Route Table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Associate private subnets
resource "aws_route_table_association" "private_1_assoc" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_2_assoc" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private_rt.id
}


# Security Groups


resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id

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

resource "aws_security_group" "ecs_sg" {
  name   = "ecs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Load Balancer


resource "aws_lb" "alb" {
  name               = "lamptey-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_lb_target_group" "tg" {
  name         = "lamptey-tg"
  port         = 5000
  protocol     = "HTTP"
  vpc_id       = aws_vpc.main.id
  target_type  = "ip"

  health_check {
    path     = "/"
    protocol = "HTTP"
    matcher  = "200"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }

  depends_on = [aws_lb_target_group.tg]
}






# COMPUTE - ECS Cluster, Task & Service

# This ECS provisions the compute layer to run containerized applications on AWS Fargate.
# Included components:
#  IAM Role for ECS task execution with necessary permissions
#  ECS Cluster to manage Fargate services
#  CloudWatch Log Group for container log aggregation
#  ECS Task Definition configured to use the latest image from ECR
#  ECS Service to run and manage desired count of tasks with load balancing and deployment rollback


locals {
  container_name = "flask-app"
  container_port = 5000
}

#ECS Cluster

resource "aws_ecs_cluster" "main" {
  name = "lamptey-cluster"
}

#Cloudwatch Log Group
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/${local.container_name}"
  retention_in_days = 7
}

#ECS Task Definition
resource "aws_ecs_task_definition" "task" {
  family                   = "lamptey-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = "${aws_ecr_repository.flask_app_repo.repository_url}:latest"
      essential = true
      portMappings = [{
        containerPort = local.container_port
        protocol      = "tcp"
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_log_group.name
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

#ECS Service
resource "aws_ecs_service" "service" {
  name            = "lamptey-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  deployment_controller {
    type = "ECS"
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = local.container_name
    container_port   = local.container_port
  }

  depends_on = [
    aws_lb_listener.listener,
    aws_cloudwatch_log_group.ecs_log_group
  ]
}


# IAM Roles


resource "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_attach" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# CodePipeline
 #CodePipeline CI/CD Infrastructure
# -----------------------------
# This section provisions a complete CI/CD pipeline that:
# Creates an Amazon ECR repository to store Docker images
# Sets up an AWS CodeBuild project to build and push images to ECR
# Defines IAM roles and inline policies for CodeBuild and CodePipeline with scoped permissions
# Creates an S3 bucket to store CodePipeline artifacts (build outputs)
# Configures a three-stage CodePipeline:
#     1. Source: Pulls code from GitHub
#     2. Build: Builds Docker image using CodeBuild
#     3. Deploy: Deploys container to ECS Fargate via imagedefinitions.json
# This setup enables automated deployments of containerized applications from GitHub
# to Amazon ECS using infrastructure-as-code with Terraform.

#CODE BUILD
#ECR REPOSITORY
resource "aws_ecr_repository" "flask_app_repo" {
  name         = "flask-rds-app"
  force_delete = true
}

#CodeBuild Project
resource "aws_codebuild_project" "build" {
  name         = "flask-app-build"
  service_role = aws_iam_role.codebuild_role.arn

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    # Use either ACCOUNT_ID or AWS_ACCOUNT_ID, not both
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "ECR_REPO_URI"
      value = aws_ecr_repository.flask_app_repo.repository_url
    }

    environment_variable {
      name  = "AWS_REGION"
      value = "us-east-1"
    }

    environment_variable {
      name  = "ECR_REPO_NAME"
      value = "flask-rds-app"
    }
  }
}

# Assume Role Policy Document - Allows CodeBuild to assume this role
# Allow CodeBuild to assume this role
data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# Create the IAM Role
resource "aws_iam_role" "codebuild_role" {
  name               = "codebuild-service-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
}

# Define inline permissions for CodeBuild
data "aws_iam_policy_document" "codebuild_permissions" {
  statement {
    sid     = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }

  statement {
    sid     = "S3Access"
    effect  = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]
    resources = ["*"]
  }

    
    
  statement {
    sid     = "ECRPushAccess"
    effect  = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]
    resources = ["*"]
  }

  statement {
    sid     = "CodeCommitAccess"
    effect  = "Allow"
    actions = [
      "codecommit:GitPull"
    ]
    resources = ["*"]
  }

  statement {
    sid     = "CodeBuildActions"
    effect  = "Allow"
    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild"
    ]
    resources = ["*"]

    
      }
}

# Attach the policy to the role
resource "aws_iam_role_policy" "codebuild_inline_policy" {
  name   = "codebuild-inline-permissions"
  role   = aws_iam_role.codebuild_role.id
  policy = data.aws_iam_policy_document.codebuild_permissions.json
}



resource "aws_s3_bucket" "artifact_store" {
  bucket        = "flask-rds-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_codepipeline" "pipeline" {
  name     = "flask-app-pipeline"
  role_arn = aws_iam_role.pipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifact_store.bucket
    type     = "S3"
  }


    
      stage {
    name = "Source"
    action {
      name             = "SourceAction"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        Owner      = "papanol"
        Repo       = "app-ecs"
        Branch     = var.github_branch
        OAuthToken = var.github_oauth_token
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "BuildAction"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"
      configuration = {

    
            ProjectName = aws_codebuild_project.build.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "DeployAction"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["build_output"]
      version         = "1"
      configuration = {
        ClusterName = aws_ecs_cluster.main.name
        ServiceName = aws_ecs_service.service.name
        FileName    = "imagedefinitions.json"
      }
    }
  }
}

resource "aws_iam_role" "pipeline_role" {
  name = "codepipeline-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "codepipeline.amazonaws.com" }, Action = "sts:AssumeRole" }]

    
      })
}

resource "aws_iam_role_policy_attachment" "pipeline_attach" {
  role       = aws_iam_role.pipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}


# Outputs

output "alb_dns" {
  value = aws_lb.alb.dns_name
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}



output "artifact_bucket" {
  value = aws_s3_bucket.artifact_store.bucket
}

output "ecr_repo_url" {
  value = aws_ecr_repository.flask_app_repo.repository_url
}

