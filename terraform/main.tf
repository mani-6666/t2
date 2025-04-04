provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_db_subnet_group" "db" {
  name       = "medusa-db-subnet-group"
  subnet_ids = aws_subnet.public[*].id
}

resource "aws_security_group" "ecs_sg" {
  name        = "ecs_sg"
  description = "Allow HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 9000
    to_port     = 9000
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

resource "aws_db_instance" "medusa_db" {
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "14.7"
  instance_class       = "db.t3.micro"
  name                 = "medusadb"
  username             = var.db_user
  password             = var.db_password
  skip_final_snapshot  = true
  publicly_accessible  = true
  db_subnet_group_name = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.ecs_sg.id]
}

resource "aws_ecs_cluster" "medusa" {
  name = "medusa-cluster"
}

resource "aws_ecs_task_definition" "medusa_task" {
  family                   = "medusa-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"

  container_definitions = jsonencode([
    {
      name      = "medusa",
      image     = var.medusa_image,
      essential = true,
      portMappings = [
        {
          containerPort = 9000,
          hostPort      = 9000
        }
      ],
      environment = [
        {
          name  = "DATABASE_URL",
          value = "postgres://${var.db_user}:${var.db_password}@${aws_db_instance.medusa_db.address}:5432/${aws_db_instance.medusa_db.name}"
        },
        {
          name  = "JWT_SECRET",
          value = var.jwt_secret
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "medusa" {
  name            = "medusa-service"
  cluster         = aws_ecs_cluster.medusa.id
  task_definition = aws_ecs_task_definition.medusa_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.public[*].id
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  depends_on = [aws_internet_gateway.igw]
}
