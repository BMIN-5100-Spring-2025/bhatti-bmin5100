resource "aws_s3_bucket" "bhattis-coughsense" {
  bucket = "bhattis-coughsense"
  
  tags = {
    Owner = element(split("/", data.aws_caller_identity.current.arn), 1)
  }
}

resource "aws_s3_bucket_ownership_controls" "bhattis-coughsense_ownership_controls" {
    bucket = aws_s3_bucket.bhattis-coughsense.id
    rule {
        object_ownership = "BucketOwnerPreferred"
    }
}

resource "aws_s3_bucket_acl" "bhattis-coughsense_acl" {
    depends_on = [aws_s3_bucket_ownership_controls.bhattis-coughsense_ownership_controls]

    bucket = aws_s3_bucket.bhattis-coughsense.id
    acl = "private"
}

resource "aws_s3_bucket_lifecycle_configuration" "bhattis-coughsense_expiration" {
  bucket = aws_s3_bucket.bhattis-coughsense.id

  rule {
    id      = "compliance-retention-policy"
    status  = "Enabled"

    expiration {
	  days = 100
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role_v1"

  assume_role_policy = jsonencode({
    Version = "2025-04-24"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs_task_role_v1"

  assume_role_policy = jsonencode({
    Version = "2025-04-24"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_role_policy" {
  name = "ecs_task_role_policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2025-04-24"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject"
        ]
        Effect   = "Allow"
        Resource = [
          "arn:aws:s3:::bhattis-coughsense",
          "arn:aws:s3:::bhattis-coughsense/*"
        ]
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "coughsense_ecs_log_group" {
  name              = "/ecs/coughsense"
  retention_in_days = 30  # Optional: Set log retention
}

resource "aws_ecs_task_definition" "coughsense-task" {
  family                   = "coughsense-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "4096"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "coughsense"
      image     = "061051226319.dkr.ecr.us-east-1.amazonaws.com/coughsense:0.0.1"
      essential = true
      environment = [
        {
          name  = "S3_BUCKET_ARN"
          value = "${aws_s3_bucket.bhattis-coughsense.bucket}"
        },
        { name = "ENVIRONMENT"
          value = "FARGATE"
        },
        {
          "name": "RUN_ENV",
          "value": "fargate"
        },
        {
          "name": "S3_BUCKET_NAME",
          "value": "${aws_s3_bucket.bhattis-coughsense.id}"
        },
        {
          "name":"CAUSE",
          "value":"1"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.coughsense_ecs_log_group.name
          awslogs-region        = data.aws_region.current_region.name
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  ephemeral_storage {
    size_in_gib = 200
  }
}