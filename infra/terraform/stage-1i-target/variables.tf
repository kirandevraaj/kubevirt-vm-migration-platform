variable "region" {
  description = "AWS Region of the disposable target."
  type        = string
  default     = "ap-south-1"
}

variable "availability_zone" {
  description = "Single AZ for the node; CSI-created EBS volumes are bound to it."
  type        = string
  default     = "ap-south-1a"
}

variable "vpc_cidr" {
  description = "VPC range. Must not overlap the pod CIDR (10.244.0.0/16), the Service CIDR (10.96.0.0/12), the masquerade CIDR (10.0.2.0/24) or CRI-O's bridge (10.85.0.0/16)."
  type        = string
  default     = "10.40.0.0/16"
}

variable "subnet_cidr" {
  description = "Public subnet inside the VPC."
  type        = string
  default     = "10.40.1.0/24"
}

variable "node_private_ip" {
  description = "Fixed private IPv4 of the node inside the subnet."
  type        = string
  default     = "10.40.1.10"
}

variable "operator_cidr" {
  description = "Operator public address as a /32. The only source allowed for TCP 22 and TCP 30080."
  type        = string

  validation {
    condition     = can(cidrhost(var.operator_cidr, 0)) && endswith(var.operator_cidr, "/32")
    error_message = "operator_cidr must be a single IPv4 address in /32 form."
  }
}

variable "ssh_public_key" {
  description = "Public half of the dedicated node SSH key, installed for ec2-user by cloud-init."
  type        = string

  validation {
    condition     = can(regex("^ssh-(ed25519|rsa) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key."
  }
}

variable "ami_id" {
  description = "Official CentOS Stream 9 x86_64 AMI, resolved at build time."
  type        = string
}

variable "ami_owner" {
  description = "Owner account of the official CentOS AMIs."
  type        = string
  default     = "125523088429"
}

variable "instance_type" {
  description = "Nested-virtualization capable instance type."
  type        = string
  default     = "m8i.xlarge"
}

variable "root_volume_size_gib" {
  description = "Encrypted gp3 root volume size."
  type        = number
  default     = 50
}
