terraform {
  backend "s3" {
    bucket         = "glps-test-backend-bucket"
    key            = "eksgame2048/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
  }
}