resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_vpc" "demo2_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "demo2_vpc"
  }
}

resource "aws_subnet" "demo2_subnet1" {
  vpc_id                  = aws_vpc.demo2_vpc.id
  availability_zone       = var.availability_zone1
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "demo2_subnet1"
  }
}

resource "aws_subnet" "demo2_subnet2" {
  vpc_id                  = aws_vpc.demo2_vpc.id
  availability_zone       = var.availability_zone2
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "demo2_subnet2"
  }
}

resource "aws_subnet" "demo2_subnet3" {
  vpc_id                  = aws_vpc.demo2_vpc.id
  availability_zone       = var.availability_zone3
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "demo2_subnet3"
  }
}

resource "aws_db_subnet_group" "demo2_db_subnet_group" {
  name        = "demo2_db_subnet_group"
  description = "demo2_db_subnet_group"
  subnet_ids  = [aws_subnet.demo2_subnet1.id, aws_subnet.demo2_subnet2.id, aws_subnet.demo2_subnet3.id]
}

resource "aws_internet_gateway" "demo2_gateway" {
  vpc_id      = aws_vpc.demo2_vpc.id
  tags = {
    Name = "demo2_gateway"
  }
}

resource "aws_route_table" "demo2_route_table" {
  vpc_id = aws_vpc.demo2_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo2_gateway.id
  }
  tags = {
    Name = "demo2_route_table"
  }
}

resource "aws_main_route_table_association" "demo2_main_route_table_association" {
  vpc_id          = aws_vpc.demo2_vpc.id
  route_table_id  = aws_route_table.demo2_route_table.id
}

# Security group to access RDS instances over Postgres port
# resource "aws_db_security_group"
resource "aws_security_group" "demo2_rds_secgroup" {
  name        = "demo2_rds_security_group"
  description = "demo2 rds security group"
  vpc_id      = aws_vpc.demo2_vpc.id

  # Access from default_vpc and demo2_vpc to RDS Postgres port
  ingress {
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.demo2_vpc.cidr_block, var.default_vpc_cidr_block]
  }
  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group to access EC2 instances over SSH and HTTP
resource "aws_security_group" "demo2_webapp_secgroup" {
  name        = "demo2_webapp_security_group"
  description = "demo2_webapp_security_group"
  vpc_id      = aws_vpc.demo2_vpc.id

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # HTTP access to webapp port from demo2_vpc for ELB only
  ingress {
    from_port   = var.webapp_port
    to_port     = var.webapp_port
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.demo2_vpc.cidr_block]
  }
  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ELB security group to access the ELB over HTTP
resource "aws_security_group" "demo2_elb_secgroup" {
  name        = "demo2_elb_security_group"
  description = "demo2_elb_security_group"
  vpc_id = aws_vpc.demo2_vpc.id

  # HTTP access to webapp port from anywhere
  ingress {
    from_port   = var.webapp_port
    to_port     = var.webapp_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Dependency is used to ensure that VPC has an Internet gateway or this step will fail
  depends_on = [aws_internet_gateway.demo2_gateway]
}

# Configure vpc peering connection between default VPC where Jenkins is running and demo2_vpc created by Terraform"
# VPC peering connection will allow Jenkins to populate RDS database using liquibase through private IP without enabling publicly_accessible option for RDS database
resource "aws_vpc_peering_connection" "demo2_vpc_peering" {
  peer_owner_id = var.aws_account_id
  peer_vpc_id   = var.default_vpc_id
  vpc_id        = aws_vpc.demo2_vpc.id
  auto_accept   = true
  tags = {
    Name = "demo2_vpc_peering_to_default_vpc"
  }
}

# Add route from default_vpc to demo2_vpc
resource "aws_route" "default_vpc_to_demo2_vpc" {
  route_table_id             = aws_default_vpc.default.default_route_table_id
  destination_cidr_block     = aws_vpc.demo2_vpc.cidr_block
  vpc_peering_connection_id  = aws_vpc_peering_connection.demo2_vpc_peering.id
}

# Add route from demo2_vpc to default_vpc
resource "aws_route" "demo2_vpc_to_default_vpc" {
  route_table_id             = aws_route_table.demo2_route_table.id
  destination_cidr_block     = aws_default_vpc.default.cidr_block
  vpc_peering_connection_id  = aws_vpc_peering_connection.demo2_vpc_peering.id
}
