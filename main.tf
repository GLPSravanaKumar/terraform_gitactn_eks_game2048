data "aws_availability_zones" "az" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = local.vpc_tags
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = element(data.aws_availability_zones.az.names, count.index)
  map_public_ip_on_launch = true
  tags = local.subnet_tags[count.index]
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = local.internetgateway_tags
}

resource "aws_eip" "eip" {
  domain = "vpc"
  tags = local.eip_tags
}

resource "aws_nat_gateway" "nat" {
  subnet_id     = aws_subnet.public[0].id
  allocation_id = aws_eip.eip.id
  tags = local.natgateway_tags
  depends_on = [aws_eip.eip]
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = local.public_rt_tags
}

resource "aws_route_table_association" "public_rt" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

/* resource "aws_iam_role" "eks_role" {
  name = "eks2048role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
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
} */

data "aws_iam_role" "eks_role" {
  name = "eks2048role"
}

resource "aws_iam_role_policy_attachment" "EKSClusterPolicy" {
  role       = data.aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "EKSVPCResourceController" {
  role       = data.aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

/* resource "aws_iam_role" "eks_node_role" {
  name = "eksNodeGroupRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
  lifecycle {
    prevent_destroy = false
  }
} */

data "aws_iam_role" "eks_node_role" {
  name = "eksNodeGroupRole"
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = data.aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = data.aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ec2_container_registry_readonly" {
  role       = data.aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "eks" {
  name     = var.cluster_name
  role_arn = data.aws_iam_role.eks_role.arn

  vpc_config {
    subnet_ids = aws_subnet.public[*].id
  }
  depends_on = [aws_iam_role_policy_attachment.EKSClusterPolicy]
  tags = local.ekscluster_tags
}

resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = data.aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.public[*].id

  scaling_config {
    desired_size = var.node_desired_capacity
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  ami_type       = var.node_ami_type  #"AL2023_x86_64_STANDARD" # Amazon Linux 2
  instance_types = [var.node_instance_type]   #["t3.medium"]
  disk_size      = var.node_disk_size   # 20

  tags = local.eksnodegroup_tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ec2_container_registry_readonly
  ]
}

resource "kubernetes_namespace" "ns" {
  count = var.enable_k8s ? 1 : 0
  metadata {
    name = var.namespace  #"game-2048"
  }
  depends_on = [
    aws_eks_cluster.eks,
    aws_eks_node_group.node_group,
    data.aws_iam_role.eks_role,
    data.aws_iam_role.eks_node_role
  ]
}

resource "kubernetes_deployment" "deploy" {
  count = var.enable_k8s ? 1 : 0
  metadata {
    name      =  var.deployment_name #"deploy-2048"
    namespace = kubernetes_namespace.ns[count.index].metadata[0].name
    labels = {
      "appication" : "app-2048"
    }
  }

  spec {
    replicas = var.replica_count
    selector {
      match_labels = {
        "appication" : "app-2048"
      }
    }
    template {
      metadata {
        labels = {
          "appication" : "app-2048"
        }
      }
      spec {
        container {
          image             = var.image #"public.ecr.aws/l6m2t8p7/docker-2048:latest"
          name              = var.cluster_name
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 80
          }
          resources {
            limits = local.limits
            requests = local.requests
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
  count = var.enable_k8s ? 1 : 0
  metadata {
    namespace = kubernetes_namespace.ns[count.index].metadata[0].name
    name      = var.service_name #"svc-2048"
  }
  spec {
    selector = {
      "appication" : "app-2048"
    }
    port {
      name        = "http"
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }
    type = var.service_type #"NodePort"
  }
  depends_on = [kubernetes_namespace.ns, kubernetes_deployment.deploy]
}

resource "kubernetes_ingress_v1" "webapp_ingress" {
  count = var.enable_k8s ? 1 : 0
  metadata {
    namespace = kubernetes_namespace.ns[count.index].metadata[0].name
    name      = var.alb_ingress_name #"ingress-2048"
    annotations = local.annotations
  }

  spec {
    ingress_class_name = "alb"
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.svc[count.index].metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.ns, kubernetes_deployment.deploy, kubernetes_service.svc]
}

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc" {
  url = aws_eks_cluster.eks.identity[0].oidc[0].issuer

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [data.tls_certificate.oidc_thumbprint.certificates[0].sha1_fingerprint]

  depends_on = [aws_eks_cluster.eks]
  lifecycle {
    prevent_destroy = false
  }
}

/* resource "aws_iam_policy" "alb_controller_policy" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  description = "Ingress controller policy for ALB"
  policy = file("${path.module}/iam_policy_alb_controller.json")
  lifecycle {
    prevent_destroy = false
  }
} */

data "aws_eks_cluster_auth" "eks" {
  name       = aws_eks_cluster.eks.id
  depends_on = [aws_eks_cluster.eks]
}

data "aws_iam_policy" "alb_controller_policy" {
  arn = "arn:aws:iam::593793035673:policy/AWSLoadBalancerControllerIAMPolicy"
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
        StringEquals = local.albcontroller_policy_condtions
      }
    }]
  })
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_iam_role_policy_attachment" "alb_controller_attach" {
  policy_arn = data.aws_iam_policy.alb_controller_policy.arn
  role       = aws_iam_role.alb_controller.name
}

resource "kubernetes_service_account" "alb_sa" {
  count = var.enable_k8s ? 1 : 0
  metadata {
    name      = var.service_acount_name #"aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn
    }
  }
  depends_on = [aws_eks_cluster.eks]
}

resource "helm_release" "alb_controller" {
  count = var.enable_k8s ? 1 : 0
  name       = var.helm_chart_name
  namespace  = "kube-system"
  repository = var.helm_repo_url #"https://aws.github.io/eks-charts"
  chart      = var.helm_chart_name
  version    = var.helm_version #"1.7.1"

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
    value = var.service_acount_name
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "vpcId"
    value = aws_vpc.main.id
  }

  depends_on = [aws_iam_role_policy_attachment.alb_controller_attach,
    aws_eks_cluster.eks, aws_vpc.main,
  kubernetes_service_account.alb_sa, kubernetes_namespace.ns, kubernetes_service.svc, kubernetes_deployment.deploy,
  kubernetes_ingress_v1.webapp_ingress]
}



/* resource "kubernetes_namespace" "monitor" {
  metadata {
    name = "monitor"
  }
  depends_on = [
    aws_eks_cluster.eks,
    aws_eks_node_group.node_group
    ]
  
} */

