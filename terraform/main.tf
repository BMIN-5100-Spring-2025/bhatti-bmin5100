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
  name = "coughsense_ecs_task_execution_role_v1"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
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
  name = "coughsense_ecs_task_role_v1"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
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
  name = "coughsense_ecs_task_role_policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
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
      image     = "061051226319.dkr.ecr.us-east-1.amazonaws.com/coughsense:0.0.4"
      essential = true
      environment = [
        { name = "INPUT_MODE",
          value = "s3"
        },
        {
          "name": "MODEL_FILENAME",
          "value": "model.pt"
        },
        {
          "name": "S3_BUCKET",
          "value": "${aws_s3_bucket.bhattis-coughsense.id}"
        },
        {
          "name":"AUDIO_FILENAME",
          "value":"PID_82A_54_codec.wav"
        },
        {
          "name":"S3_KEY",
          "value":"audio_files/"
        },
        {
          "name":"OUTPUT_DIR",
          "value":"/data/output"
        },
        {
          "name":"INPUT_DIR",
          "value":"/data/input"
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

resource "aws_s3_bucket_cors_configuration" "bhattis-coughsense_cors_configuration" {
  bucket = aws_s3_bucket.bhattis-coughsense.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "POST", "PUT", "HEAD"]
    allowed_origins = ["http://localhost:5173", "bmin-5100.com", "*.bmin-5100.com"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

module "invoke_fargate_lambda" {
  source = "git@github.com:BMIN-5100-Spring-2025/infrastructure.git//invoke_fargate_lambda/terraform"

  project_name = "coughsense"
  ecs_task_definition_arn = aws_ecs_task_definition.coughsense-task.arn
  ecs_task_execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  ecs_task_task_role_arn = aws_iam_role.ecs_task_role.arn
  ecs_task_definition_container_name = "coughsense"

  ecs_cluster_arn = data.terraform_remote_state.infrastructure.outputs.ecs_cluster_arn
  ecs_security_group_id = data.terraform_remote_state.infrastructure.outputs.ecs_security_group_id
  private_subnet_id = data.terraform_remote_state.infrastructure.outputs.private_subnet_id
  api_gateway_authorizer_id = data.terraform_remote_state.infrastructure.outputs.api_gateway_authorizer_id
  api_gateway_execution_arn = data.terraform_remote_state.infrastructure.outputs.api_gateway_execution_arn
  api_gateway_id = data.terraform_remote_state.infrastructure.outputs.api_gateway_id
  environment_variables = {}
}