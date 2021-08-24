provider "aws" {
    region = "eu-west-1"
}



# Create an EC2 Instance
# First create a vpc group
resource "aws_vpc" "terraform_ec2_vpc" {
  cidr_block = "10.0.0.0/16"
}


# # Then Create a subnet
# resource "aws_subnet" "terraform_ec2_subnet" {
#   vpc_id            = aws_vpc.terraform_ec2_vpc.id
#   cidr_block        = aws_vpc.terraform_ec2_vpc.cidr_block
#   availability_zone = "eu-west-1a"

#   tags = {
#     Name = "tf-project"
#   }
# }


# # Then Create a network interface
# resource "aws_network_interface" "terraform_ec2_ni" {
#   subnet_id   = aws_subnet.terraform_ec2_subnet.id
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
#     instance_type = "t3.micro"
#     key_name = "terraform_project"

#     network_interface {
#         network_interface_id = aws_network_interface.terraform_ec2_ni.id
#         device_index         = 0
#     }

#     tags = {
#         Name = "Terraform Ec2 Instance"
#     }
# }



