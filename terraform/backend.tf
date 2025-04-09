terraform {
    backend "s3" {
        bucket = "bmin5100-terraform-state"
        key = "sabhatti@seas.upenn.edu-coughsense/terraform.tfstate"
        region = "us-east-1"
        encrypt = true
    }
}