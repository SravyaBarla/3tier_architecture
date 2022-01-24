terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.72.0" #aws version
    }
  }
  required_version = ">=0.14.9" #terraform version
}

#Providers allow Terraform to interact with cloud providers, SaaS providers, and other APIs. 
provider "aws" {
  profile = "default"
  region     = var.region
  
}
#tenancy defines how EC2 instances are distributed across physical hardware and affects pricing. ... Shared ( default ) — Multiple AWS accounts may share the same physical hardware. Dedicated Instance ( dedicated ) — Your instance runs on single-tenant hardware.

resource "aws_vpc" "terraform_vpc" {
  cidr_block       = var.vpc_cidr_block
  instance_tenancy = var.instance_tenancy

  tags = {
    Name = var.vpc_name
  }
}
#Classless Inter-Domain Routing is a method for allocating IP addresses and for IP routing
resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.terraform_vpc.id
  cidr_block        = var.public_subnet_cidr_block_1 #optional
  availability_zone = var.public_subnet_1_az #optional

  tags = {
    Name = var.public_subnet_name_1
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.terraform_vpc.id
  cidr_block        = var.public_subnet_cidr_block_2
  availability_zone = var.public_subnet_2_az

  tags = {
    Name = var.public_subnet_name_2
  }
}

resource "aws_subnet" "private_subnet_1" {
  cidr_block        = var.private_subnet_cidr_block_1
  vpc_id            = aws_vpc.terraform_vpc.id
  availability_zone = var.private_subnet_1_az

  tags = {
    Name = var.tagkey_name_private_subnet_1
  }
}
#An internet gateway is a horizontally scaled, redundant, and highly available VPC component that allows communication between your VPC and the internet
resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.terraform_vpc.id
}

resource "aws_route_table" "public_subnet_1_to_internet" {
  vpc_id = aws_vpc.terraform_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }

  tags = {
    Name = var.public_route_table_1
  }
}

resource "aws_route_table" "public_subnet_2_to_internet" {
  vpc_id = aws_vpc.terraform_vpc.id

  route {
    cidr_block = "0.0.0.0/0" #required
    gateway_id = aws_internet_gateway.default.id #optional
  }

  tags = {
    Name = var.public_route_table_2
  }
}

resource "aws_route_table_association" "internet_for_public_subnet_1" {
  route_table_id = aws_route_table.public_subnet_1_to_internet.id #required
  subnet_id      = aws_subnet.public_subnet_1.id #optional ( The subnet ID to create an association. Conflicts with gateway_id)
}

resource "aws_route_table_association" "internet_for_public_subnet_2" {
  route_table_id = aws_route_table.public_subnet_2_to_internet.id
  subnet_id      = aws_subnet.public_subnet_2.id
}
#An Elastic IP address is a static IPv4 address designed for dynamic cloud computing
resource "aws_eip" "eip_1" {
  count = "1"
}

resource "aws_nat_gateway" "natgateway_1" {
  count         = "1"
  allocation_id = aws_eip.eip_1[count.index].id
  subnet_id     = aws_subnet.public_subnet_1.id #required
}

resource "aws_route_table" "natgateway_route_table_1" {
  count  = "1"
  vpc_id = aws_vpc.terraform_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natgateway_1[count.index].id
  }

  tags = {
    Name = var.tagkey_name_natgateway_route_table_1
  }
}

resource "aws_route_table_association" "private_subnet_1_to_natgateway" {
  count          = "1"
  route_table_id = aws_route_table.natgateway_route_table_1[count.index].id
  subnet_id      = aws_subnet.private_subnet_1.id
}

#transport layer security
resource "tls_private_key" "public_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_key" {
  key_name   = var.key_name #optional
  public_key = tls_private_key.public_key.public_key_openssh #required
}

locals {
  subs = concat([aws_subnet.public_subnet_1.id], [aws_subnet.public_subnet_2.id])
}

resource "aws_instance" "terraform_ec2" {
  count                       = var.ec2_count
  ami                         = var.ec2_ami
  instance_type               = var.ec2_instance_type
  key_name                    = aws_key_pair.ec2_key.key_name
  vpc_security_group_ids      = [aws_security_group.alb_sg.id]
  subnet_id                   = element(local.subs, 2)
  associate_public_ip_address = var.associate_public_ip_address_bool
}


resource "aws_db_instance" "rds_mysql_instance" {
  allocated_storage      = var.rds_allocated_storage #required
  engine                 = var.rds_engine #required
  engine_version         = var.rds_engine_version
  instance_class         = var.rds_instance_class
  name                   = var.rds_name
  username               = var.rds_username #required
  password               = var.rds_password
  parameter_group_name   = var.rds_parameter_group_name #(Optional) Name of the DB parameter group to associate
  skip_final_snapshot    = var.rds_skip_final_snapshot
  publicly_accessible    = var.rds_publicly_accessible
  vpc_security_group_ids = [aws_security_group.alb_sg.id]
}

resource "aws_security_group" "alb_sg" {
  name        = var.sg_name
  description = var.sg_description
  vpc_id      = aws_vpc.terraform_vpc.id

  ingress {
    from_port   = var.rds_from_port #required
    to_port     = var.rds_to_port #required
    protocol    = "tcp" #required
    description = "MySQL"
    self        = true #(Optional) Whether the security group itself will be added as a source to this ingress rule
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    description = "HTTP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    description = "HTTPS"
    self        = true
  }

  egress {
    from_port   = var.sg_egress_from_port #required
    to_port     = var.sg_egress_to_port #required
    protocol    = var.sg_egress_protocol #required, If you select a protocol of -1 (semantically equivalent to all, which is not a valid value here), you must specify a from_port and to_port equal to 0
    cidr_blocks = var.sg_egress_cidr_blocks
  }

  tags = {
    Name = var.sg_tagname
  }
}

resource "aws_alb" "alb" {
  name               = var.alb_name
  internal           = var.alb_internal #if true then alb is internal
  load_balancer_type = var.load_balancer_type
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id] #(Optional) A list of subnet IDs to attach to the LB. Subnets cannot be updated for Load Balancers of type network. Changing this value for load balancers of type network will force a recreation of the resource.

  enable_deletion_protection = var.enable_deletion_protection

  tags = {
    Environment = var.alb_tagname
  }
}
