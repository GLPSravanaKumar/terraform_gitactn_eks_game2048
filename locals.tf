locals {

    vpc_tags = {
        Name = "${var.cluster_name}/vpc"
        "kubernetes.io/role/elb" = "1"
        "kubernetes.io/ingress.class" = "1"
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
    subnet_tags = [
        for idx in range(length(var.public_subnet_cidrs)) : {
        Name                                        = "${var.cluster_name}/public-subnet-${idx}"
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        "kubernetes.io/role/elb"                    = "1"
        "kubernetes.io/ingress.class"               = "1"
        }
    ]
    internetgateway_tags = {
        Name = "${var.cluster_name}/igw"
    }
    eip_tags = {
        Name = "${var.cluster_name}/eip"
    }
    natgateway_tags = {
        Name = "${var.cluster_name}/nat-gateway"
    }
    public_rt_tags = {
        Name = "${var.cluster_name}/public-rt"
    }
    ekscluster_tags = {
        Name = "${var.cluster_name}/cluster"
    }
    eksnodegroup_tags = {
         Name                                              = "${var.cluster_name}/node_group"
        "kubernetes.io/cluster/${aws_eks_cluster.eks.name}" = "owned"  
    }
    limits = {
        cpu    =  var.cpu_limits #"500m"
        memory = var.memory_limits #"512Mi"
    }
    requests = {
        cpu    = var.cpu_requests #"250m"
        memory = var.memory_requests #"256Mi"
    }
    annotations = {
      "kubernetes.io/ingress.class"                     = "alb"
      "alb.ingress.kubernetes.io/scheme"       = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"  = "ip"
      "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\": 80}]"
    }
    
    albcontroller_policy_condtions = {
        "${replace(aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:${var.service_acount_name}"
        "${replace(aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
    }
    
    

}