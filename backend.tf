terraform {
  backend "s3" {
    bucket         = "optum-prod-bkt"
    key            = "terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
  }
}