variable "region" {
  default = "us-east-1"
}

variable "cluster_name" {
  default = "glps-eks-game2048"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.5.0/24"]
}

