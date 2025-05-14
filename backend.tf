terraform {
  backend "s3" {
    bucket         = "glps-test-backend-bucket"
    key            = "terraform_gitactn_eks_game2048/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
  }
}