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