variable "region" {}
variable "cluster_name" {}
variable "vpc_cidr" {}
variable "public_subnet_cidrs" {}
variable "enable_k8s" {
  type    = bool
  default = true
}
# variables mentioned in main.tf
variable "node_desired_capacity" {}
variable "node_max_size" {}
variable "node_min_size" {}
variable "node_ami_type" {}
variable "node_instance_type"{}
variable "node_disk_size" {}
variable "namespace" {}
variable "deployment_name" {}
variable "replica_count" {}
variable "image" {}
variable "cpu_limits" {}
variable "memory_limits" {}
variable "cpu_requests" {}
variable "memory_requests" {}
variable "service_name" {}
variable "service_type" {}
variable "alb_ingress_name" {}
variable "service_acount_name" {}
variable "helm_repo_url" {}
variable "helm_chart_name" {}
variable "helm_version" {}












