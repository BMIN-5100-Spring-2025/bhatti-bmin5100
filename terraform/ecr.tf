resource "aws_ecr_repository" "coughsense" {
  name                 = "coughsense"

  image_scanning_configuration {
    scan_on_push = true
  }

tags = {
    Name        = "coughsense"
    Environment = "dev"
  }
}