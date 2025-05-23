data "aws_availability_zones" "az" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    Name = "${var.cluster_name}/vpc"
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)
  vpc_id = aws_vpc.main.id
  cidr_block = var.public_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.az.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name                                        = "${var.cluster_name}/public-subnet-${count.index}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "kubernetes.io/role/alb"                    = "1"
    "kubernetes.io/role/elb"                    = "1" 
    "kubernetes.io/role/internal-elb"           = "1" 
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.cluster_name}/igw"
  }
}

resource "aws_eip" "eip" {
  domain = "vpc"
  tags = {
    Name = "${var.cluster_name}/eip"
  }
}

resource "aws_nat_gateway" "nat" {
  subnet_id = aws_subnet.public[0].id
  allocation_id = aws_eip.eip.id
  tags = {
    Name = "${var.cluster_name}/nat-gateway"
  }
  depends_on = [ aws_eip.eip ]
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags ={
    Name = "${var.cluster_name}/public_rt"
  }
}

resource "aws_route_table_association" "public_rt" {
  count = length(var.public_subnet_cidrs)
  subnet_id = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_iam_role" "eks_role" {
  name = "eks2048role"
  assume_role_policy = jsonencode({
    Version          = "2012-10-17"
    Statement        = [
      {
        Action       = ["sts:AssumeRole","sts:TagSession"]
        Effect       = "Allow"
        Principal    = {
          Service    = "eks.amazonaws.com"
        }
      }
    ]
  })
  lifecycle {
    prevent_destroy = false
  }
  tags = {
    Name = "${var.cluster_name}/eks-role"
  }
}

resource "aws_iam_role_policy_attachment" "EKSClusterPolicy" {
  role       = aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "EKSVPCResourceController" {
  role       = aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_iam_role" "eks_node_role" {
  name = "eksNodeGroupRole"

  assume_role_policy = jsonencode({
    Version          = "2012-10-17"
    Statement        = [{
      Effect         = "Allow"
      Principal      = {
        Service      = "ec2.amazonaws.com"
      }
      Action         = "sts:AssumeRole"
    }]
  })
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ec2_container_registry_readonly" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

data "aws_eks_cluster" "cluster" {
  name = "your-cluster-name"
}

data "aws_eks_cluster_auth" "cluster" {
  name = data.aws_eks_cluster.cluster.name
}

data "aws_iam_openid_connect_provider" "oidc" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_role" "ebs_csi_driver" {
  name = "AmazonEKS_EBS_CSI_DriverRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.oidc.arn
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })
}


resource "aws_eks_addon" "ebs_csi" {
  cluster_name = var.cluster_name
  addon_name   = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn
}

resource "aws_iam_role_policy_attachment" "ebs_drive_policy" {
  role = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}


resource "aws_eks_cluster" "eks" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_role.arn

  vpc_config {
    subnet_ids = concat(
      aws_subnet.public[*].id,
      )
    }  

    depends_on = [aws_iam_role_policy_attachment.EKSClusterPolicy]

    tags = {
      Name = "${var.cluster_name}/cluster"
    }
}

resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.public[*].id

  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 1
  }

  ami_type       = "AL2_x86_64"  # Amazon Linux 2
  instance_types = ["t3.medium"]
  disk_size      = 20

  tags = {
    "Name" = "${var.cluster_name}/node_group"
    "kubernetes.io/cluster/${aws_eks_cluster.eks.name}" = "owned"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ec2_container_registry_readonly
    ]
}

resource "kubernetes_namespace" "ns" {
  metadata {
    name = "game-2048"
  }
  depends_on = [
    aws_eks_cluster.eks,
    aws_eks_node_group.node_group
    ]
}

resource "kubernetes_deployment" "deploy" {
  metadata {
    name = "deploy-2048"
    namespace = kubernetes_namespace.ns.metadata[0].name
    labels = {
      "app.kubernetes.io/name": "app-2048"
    }
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        "app.kubernetes.io/name": "app-2048"
      }
    }
    template {
      metadata {
        labels = {
          "app.kubernetes.io/name": "app-2048"
        }
      }
      spec {
        container {
          image = "public.ecr.aws/l6m2t8p7/docker-2048:latest"
          name  = "container-2048"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 80
          }
          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
  depends_on = [
    kubernetes_namespace.ns
  ]
}

resource "kubernetes_service" "svc" {
  metadata {
    namespace = kubernetes_namespace.ns.metadata[0].name
    name = "svc-2048"
  }
  spec {
    selector = {
      "app.kubernetes.io/name": "app-2048"
    }
    port {
      name        = "http"
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }
    type = "NodePort"
  }
  depends_on = [kubernetes_deployment.deploy]
}

resource "aws_iam_openid_connect_provider" "oidc" {
  url = aws_eks_cluster.eks.identity[0].oidc[0].issuer

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [data.tls_certificate.oidc_thumbprint.certificates[0].sha1_fingerprint]

  depends_on = [ aws_eks_cluster.eks] 
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_iam_policy" "alb_controller_policy" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  description = "Ingress controller policy for ALB"
  policy = file("${path.module}/iam_policy_alb_controller.json")
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_iam_role" "alb_controller" {
  name = "eks2048-alb-controller-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity",
      Effect = "Allow",
      Principal = {
        Federated = aws_iam_openid_connect_provider.oidc.arn
      },  
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.oidc.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_iam_role_policy_attachment" "alb_controller_attach" {
  policy_arn = aws_iam_policy.alb_controller_policy.arn
  role       = aws_iam_role.alb_controller.name
}

resource "kubernetes_service_account" "alb_sa" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn
    }
  }
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.7.1"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "region"
    value = var.region
  }
  depends_on = [aws_iam_role_policy_attachment.alb_controller_attach]
}

resource "kubernetes_ingress_v1" "webapp_ingress" {
  metadata {
    namespace = kubernetes_namespace.ns.metadata[0].name
    name = "ingress-2048"
    annotations = {
      "kubernetes.io/ingress.class"                     = "alb"
      "alb.ingress.kubernetes.io/scheme"                = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"           = "ip"
      "alb.ingress.kubernetes.io/listen-ports"          = "[{\"HTTP\": 80}]"
    }
  }

  spec {
    ingress_class_name = "alb"
    rule {
      http {
        path {
          path     = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.svc.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.alb_controller]
}

resource "kubernetes_namespace" "monitor" {
  metadata {
    name = "monitor"
  }
  depends_on = [
    aws_eks_cluster.eks,
    aws_eks_node_group.node_group
    ]
  
}

