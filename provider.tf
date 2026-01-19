terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.11"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

# AWS provider
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Environment = "Production"
      Project     = "WebAppOnEKS"
      Owner       = "glps"
    }
  }
}

# 1. Fetch EKS cluster information

# 2. Fetch EKS cluster auth informatio


data "tls_certificate" "oidc_thumbprint" {
  url        = aws_eks_cluster.eks.identity[0].oidc[0].issuer
  depends_on = [aws_eks_cluster.eks]
}


# Add to provider.tf or main.tf
provider "kubernetes" {
  host                   = var.enable_k8s ? aws_eks_cluster.eks.endpoint : null
  cluster_ca_certificate = var.enable_k8s ? base64decode(aws_eks_cluster.eks.certificate_authority[0].data) : null
  token                  = var.enable_k8s ? data.aws_eks_cluster_auth.eks.token : null
}


provider "helm" {
  kubernetes {
    host                   = var.enable_k8s ? aws_eks_cluster.eks.endpoint : null
    cluster_ca_certificate = var.enable_k8s ? base64decode(aws_eks_cluster.eks.certificate_authority[0].data) : null
    token                  = var.enable_k8s ? data.aws_eks_cluster_auth.eks.token : null
  }
}