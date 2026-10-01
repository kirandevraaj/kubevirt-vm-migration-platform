locals {
  name = "stage1i"

  tags = {
    Project   = "kubevirt-vm-migration-platform"
    Stage     = "1I"
    ManagedBy = "terraform"
    Lifecycle = "disposable"
  }
}

data "aws_partition" "current" {}

data "aws_ami" "node" {
  owners = [var.ami_owner]

  filter {
    name   = "image-id"
    values = [var.ami_id]
  }
}

# Network

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

resource "aws_subnet" "this" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-subnet" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${local.name}-igw" }
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${local.name}-rt" }
}

resource "aws_route_table_association" "this" {
  subnet_id      = aws_subnet.this.id
  route_table_id = aws_route_table.this.id
}

resource "aws_security_group" "node" {
  name        = "${local.name}-node"
  description = "Stage 1I node: TCP 22 and TCP 30080 from the operator /32 only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH to the node sshd from the operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.operator_cidr]
  }

  ingress {
    description = "HTTP validation NodePort from the operator"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = [var.operator_cidr]
  }

  egress {
    description = "All outbound: packages, images, AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-node" }
}

# IAM: instance profile for the EBS CSI driver; no static credentials

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.name}-node"
  description        = "Stage 1I node role: EBS CSI driver only"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}

resource "aws_iam_instance_profile" "node" {
  name = "${local.name}-node"
  role = aws_iam_role.node.name
}

# Node

resource "aws_instance" "node" {
  ami                         = data.aws_ami.node.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.this.id
  private_ip                  = var.node_private_ip
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.node.id]
  iam_instance_profile        = aws_iam_instance_profile.node.name

  user_data = templatefile("${path.module}/user-data.yaml.tftpl", {
    ssh_public_key = var.ssh_public_key
  })
  user_data_replace_on_change = true

  cpu_options {
    nested_virtualization = "enabled"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gib
    encrypted             = true
    delete_on_termination = true

    tags = { Name = "${local.name}-node-root" }
  }

  tags = { Name = "${local.name}-node" }

  lifecycle {
    precondition {
      condition     = data.aws_ami.node.architecture == "x86_64" && startswith(data.aws_ami.node.name, "CentOS Stream 9 x86_64")
      error_message = "ami_id must be an official CentOS Stream 9 x86_64 AMI."
    }
  }

  depends_on = [aws_route_table_association.this, aws_iam_role_policy_attachment.ebs_csi]
}
