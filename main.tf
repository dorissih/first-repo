# provider "aws" {
#     region = "eu-west-1"
#     # profile = "terraform_project"
# }



# # Create an EC2 Instance
# # First create a vpc group
# resource "aws_vpc" "terraform_ec2_vpc" {
#   cidr_block = "10.0.0.0/16"
# }


# # Then Create a subnet
# resource "aws_subnet" "terraform_ec2_public_subnet" {
#   vpc_id            = aws_vpc.terraform_ec2_vpc.id
#   cidr_block        = aws_vpc.terraform_ec2_vpc.cidr_block
#   availability_zone = "eu-west-1a"
#   map_public_ip_on_launch = true

#   tags = {
#     Name = "tf-project"
#   }
# }


# # Then Create a network interface
# resource "aws_network_interface" "terraform_ec2_ni" {
#   subnet_id   = aws_subnet.terraform_ec2_public_subnet.id
#   tags = {
#     Name = "primary_network_interface"
#   }
# }


# # Then create a security group
# resource "aws_security_group" "terraform_ec2_sg" {
#   name        = "terraform_ec2_sg"
#   description = "terraform project sg for ec2 instance"
#   vpc_id      = aws_vpc.terraform_ec2_vpc.id

#   ingress {
#       description      = "TLS from VPC"
#       from_port        = 22
#       to_port          = 22
#       protocol         = "tcp"
#       cidr_blocks      = [aws_vpc.terraform_ec2_vpc.cidr_block]
#     }
  

#   egress {
#       from_port        = 22
#       to_port          = 22
#       protocol         = "tcp"
#       cidr_blocks      = ["0.0.0.0/0"]
#     }
  
# }


# # ami-0a8e758f5e873d1c1

# # Creating the aws resource
# variable "amiid" {
#     default = "ami-0a8e758f5e873d1c1"
# }

# resource "aws_instance" "terraform_ec2_instance" {
#     ami = var.amiid
#     instance_type = "t2.micro"
#     key_name = "terraform_project"

#     network_interface {
#         network_interface_id = aws_network_interface.terraform_ec2_ni.id
#         device_index         = 0
#     }

#     tags = {
#         Name = "Terraform Ec2 Instance"
#     }
# }




# # In Jenkins Job Creation
# # A workspace directory terraform-plugin will be created, this is where temporary files are created and automatically deleted after runs.
# # This directory also contains the generated tfstate file terraform-plugin.tfstate.
# # This generated tfstate file is not deleted and is always passed to Terraform using -state=workspace/terraform-plugin/terraform-plugin.tfstate as an extra safety measure so as to not use any other tfstate file you might have in a workspace.




























provider "aws" {
    region = "eu-west-1"
    profile = "terraform_project"
}



# Create an EC2 Instance
# First create a vpc group
resource "aws_vpc" "terraform_ec2_vpc" {
  cidr_block = "10.0.0.0/16"
}


# Then Creat subnets

# Public subnet
resource "aws_subnet" "terraform_ec2_public_subnet" {
  depends_on = [
    aws_vpc.terraform_ec2_vpc
  ]

  vpc_id            = aws_vpc.terraform_ec2_vpc.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = "eu-west-1a"

  tags = {
    Name = "tf-project-public-subnet"
  }

  map_public_ip_on_launch = true

}


# Private subnet
resource "aws_subnet" "terraform_ec2_private_subnet" {
  depends_on = [
    aws_vpc.terraform_ec2_vpc
  ]

  vpc_id            = aws_vpc.terraform_ec2_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-1a"

  tags = {
    Name = "tf-project-private-subnet"
  }
}


# internet gateway
resource "aws_internet_gateway" "terraform_ec2_internet_gateway" {
  depends_on = [
    aws_vpc.terraform_ec2_vpc,
  ]

  vpc_id = aws_vpc.terraform_ec2_vpc.id

  tags = {
    Name = "terraform_ec2_internet-gateway"
  }
}



# route table with target as internet gateway
resource "aws_route_table" "terraform_ec2_IG_route_table" {
  depends_on = [
    aws_vpc.terraform_ec2_vpc,
    aws_internet_gateway.terraform_ec2_internet_gateway,
  ]

  vpc_id = aws_vpc.terraform_ec2_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.terraform_ec2_internet_gateway.id
  }

  tags = {
    Name = "terraform_ec2_IG-route-table"
  }
}

# associate route table to public subnet
resource "aws_route_table_association" "terraform_ec2_associate_routetable_to_public_subnet" {
  depends_on = [
    aws_subnet.terraform_ec2_public_subnet,
    aws_route_table.terraform_ec2_IG_route_table,
  ]
  subnet_id      = aws_subnet.terraform_ec2_public_subnet.id
  route_table_id = aws_route_table.terraform_ec2_IG_route_table.id
}



# elastic ip
resource "aws_eip" "terraform_ec2_elastic_ip" {
  vpc      = true
}

# NAT gateway
resource "aws_nat_gateway" "terraform_ec2_nat_gateway" {
  depends_on = [
    aws_subnet.terraform_ec2_public_subnet,
    aws_eip.terraform_ec2_elastic_ip,
  ]
  allocation_id = aws_eip.terraform_ec2_elastic_ip.id
  subnet_id     = aws_subnet.terraform_ec2_public_subnet.id

  tags = {
    Name = "terraform_ec2_nat-gateway"
  }
}

# route table with target as NAT gateway
resource "aws_route_table" "terraform_ec2_NAT_route_table" {
  depends_on = [
    aws_vpc.terraform_ec2_vpc,
    aws_nat_gateway.terraform_ec2_nat_gateway,
  ]

  vpc_id = aws_vpc.terraform_ec2_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.terraform_ec2_nat_gateway.id
  }

  tags = {
    Name = "terraform_ec2_NAT-route-table"
  }
}

# associate route table to private subnet
resource "aws_route_table_association" "terraform_ec2_associate_routetable_to_private_subnet" {
  depends_on = [
    aws_subnet.terraform_ec2_private_subnet,
    aws_route_table.terraform_ec2_NAT_route_table,
  ]
  subnet_id      = aws_subnet.terraform_ec2_private_subnet.id
  route_table_id = aws_route_table.terraform_ec2_NAT_route_table.id
}



# Then create a security group
resource "aws_security_group" "terraform_ec2_sg" {
  depends_on = [
    aws_vpc.terraform_ec2_vpc
  ]

  name        = "terraform_ec2_sg"
  description = "terraform project sg for ec2 instance"
  vpc_id      = aws_vpc.terraform_ec2_vpc.id

  ingress {
      description      = "Allow SSH"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
    }
  

  egress {
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
    }
  
}


# ami-0a8e758f5e873d1c1

# Creating the aws resource
variable "amiid" {
    default = "ami-0a8e758f5e873d1c1"
}

resource "aws_instance" "terraform_ec2_instance" {
    depends_on = [
      aws_security_group.terraform_ec2_sg
    ]

    ami = var.amiid
    instance_type = "t2.micro"
    key_name = "terraform_project"
    subnet_id = aws_subnet.terraform_ec2_public_subnet.id
    vpc_security_group_ids = [aws_security_group.terraform_ec2_sg.id]

    tags = {
        Name = "Terraform Ec2 Instance"
    }
}




# In Jenkins Job Creation
# A workspace directory terraform-plugin will be created, this is where temporary files are created and automatically deleted after runs.
# This directory also contains the generated tfstate file terraform-plugin.tfstate.
# This generated tfstate file is not deleted and is always passed to Terraform using -state=workspace/terraform-plugin/terraform-plugin.tfstate as an extra safety measure so as to not use any other tfstate file you might have in a workspace.