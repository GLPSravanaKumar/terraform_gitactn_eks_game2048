# variables information for terraform configuration

region = "ap-south-1"
cluster_name = "game2048-glps-ekscluster"
vpc_cidr = "10.0.0.0/16"
public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
# Instance type for nodes
node_desired_capacity = 1
node_max_size = 2
node_min_size = 1
node_ami_type = "AL2023_x86_64_STANDARD"
node_instance_type = "t3.medium"
node_disk_size = 20
namespace = "game2048"
deployment_name = "game2048-deploy"
replica_count = 2
image = "public.ecr.aws/l6m2t8p7/docker-2048:latest"
cpu_limits = "500m"
memory_limits = "512Mi"
cpu_requests = "250m"
memory_requests = "256Mi"
service_name = "game2048-svc"
service_type = "NodePort"
alb_ingress_name = "game2048-ingress"
service_acount_name = "game2048-service-account"
helm_chart_name = "aws-load-balancer-controller"
helm_repo_url = "https://aws.github.io/eks-charts"
helm_version = "1.7.1"





