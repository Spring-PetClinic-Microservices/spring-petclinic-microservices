# terraform/aws/infrastructure.tf

# -----------------------------------------------------------------------
# NETWORKING — VPC (Virtual Private Cloud)
# AWS equivalent of Azure VNet
# -----------------------------------------------------------------------

# Fetch available availability zones in this region
data "aws_availability_zones" "available" {}

# Fetches information about the current AWS account (account ID, user ARN, etc.)
data "aws_caller_identity" "current" {}

# The VPC is your isolated network in AWS
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true    # Required for EKS

  tags = {
    Name        = "petclinic-vpc"
    environment = var.environment
  }
}

# Public subnets — resources here can reach the internet (Load Balancers go here)
resource "aws_subnet" "public" {
  count             = 2    # 2 subnets for high availability (in 2 different AZs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "petclinic-public-${count.index}"
    "kubernetes.io/role/elb" = "1"    # Tells EKS this is for external load balancers
  }
}

# Private subnets — EKS worker nodes and database go here (no direct internet access)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name                              = "petclinic-private-${count.index}"
    "kubernetes.io/role/internal-elb" = "1"    # Tells EKS this is for internal load balancers
  }
}

# Internet Gateway — allows the VPC to communicate with the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# NAT Gateway — allows private subnet resources to reach the internet (for pulling images, etc.)
# without being directly reachable from the internet
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id    # NAT Gateway sits in a public subnet
}

# Route tables define where network traffic goes
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id    # Public traffic goes to internet
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id    # Private traffic goes through NAT
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------
# ECR — Elastic Container Registry (Docker image storage)
# One repository per microservice
# -----------------------------------------------------------------------
locals {
  services = [
    "config-server", "discovery-server", "api-gateway",
    "customers-service", "vets-service", "visits-service",
    "admin-server", "genai-service"
  ]
}

resource "aws_ecr_repository" "services" {
  for_each             = toset(local.services)
  name                 = "petclinic/${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true    # Automatically scan images for known vulnerabilities
  }
}

# -----------------------------------------------------------------------
# IAM ROLES FOR EKS
# EKS needs IAM roles to call AWS services on your behalf
# -----------------------------------------------------------------------

# Role for the EKS control plane
data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "petclinic-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# Role for EKS worker nodes
data "aws_iam_policy_document" "nodes_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_nodes" {
  name               = "petclinic-eks-nodes-role"
  assume_role_policy = data.aws_iam_policy_document.nodes_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# -----------------------------------------------------------------------
# EKS CLUSTER
# -----------------------------------------------------------------------
resource "aws_eks_cluster" "main" {
  name     = "petclinic-eks-${var.environment}"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.32"

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true    # For initial setup; consider restricting in production
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# Worker nodes (the EC2 instances that run your pods)
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "petclinic-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id    # Nodes go in private subnets
  instance_types  = ["t3.medium"]               # 2 vCPUs, 4GB RAM each

  scaling_config {
    desired_size = 3
    min_size     = 2
    max_size     = 5
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ecr_read_only,
  ]
}

# -----------------------------------------------------------------------
# RDS MYSQL
# -----------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name       = "petclinic-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_security_group" "rds" {
  name   = "petclinic-rds-sg"
  vpc_id = aws_vpc.main.id

  # Only allow MySQL traffic from within the VPC
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
}

resource "aws_db_instance" "main" {
  identifier             = "petclinic-mysql-${var.environment}"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.medium"
  allocated_storage      = 20
  storage_encrypted      = true    # Always encrypt data at rest
  db_name                = "petclinic"
  username               = "petclinicadmin"
  password               = var.mysql_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  multi_az               = true    # Automatic failover for high availability
  backup_retention_period = 7
}
