terraform {
  backend "s3" {
    bucket         = "optum-prod-bkt"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}