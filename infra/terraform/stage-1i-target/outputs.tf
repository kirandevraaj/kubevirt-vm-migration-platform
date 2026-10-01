output "region" {
  value = var.region
}

output "availability_zone" {
  value = aws_instance.node.availability_zone
}

output "ami_id" {
  value = data.aws_ami.node.id
}

output "ami_name" {
  value = data.aws_ami.node.name
}

output "ami_creation_date" {
  value = data.aws_ami.node.creation_date
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "subnet_id" {
  value = aws_subnet.this.id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.this.id
}

output "route_table_id" {
  value = aws_route_table.this.id
}

output "security_group_id" {
  value = aws_security_group.node.id
}

output "iam_role_name" {
  value = aws_iam_role.node.name
}

output "iam_role_arn" {
  value = aws_iam_role.node.arn
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.node.name
}

output "instance_profile_arn" {
  value = aws_iam_instance_profile.node.arn
}

output "instance_id" {
  value = aws_instance.node.id
}

output "instance_type" {
  value = aws_instance.node.instance_type
}

output "private_ip" {
  value = aws_instance.node.private_ip
}

output "public_ip" {
  value = aws_instance.node.public_ip
}

output "root_volume_id" {
  value = aws_instance.node.root_block_device[0].volume_id
}

output "operator_cidr" {
  value = var.operator_cidr
}
