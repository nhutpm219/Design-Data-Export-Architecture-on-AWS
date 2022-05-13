variable "tags" {
  default = {
    "owner"   = "rahook"
    "project" = "work-nifi"
    "client"  = "Internal"
  }
}

# 185.10.221.0/24 - airbnb
# 94.101.220.0/24 - NZ guest network
variable "nifi_inbound" {
  type    = list
  default = ["185.10.221.0/24", "94.101.220.0/24"]
}

variable "nifi_user" {
  default = "ec2-user"
}

variable "nifi_ami_name" {
  default = "amzn2-ami-hvm-2.0.20180810-x86_64-ebs"
}

variable "nifi_instance_type" {
  default = "t2.micro"
}

variable "root_vol_size" {
  default = 10
}

# 172.16.0.0 - 172.16.255.255
variable "bastion_vpc_cidr" {
  default = "172.31.0.0/16"
}

# 172.16.10.0 - 172.16.10.63
variable "bastion_subnet_cidr" {
  default = "172.31.32.0/20"
}

/* variables to inject via terraform.tfvars */
variable "aws_region" {}

variable "aws_account_id" {}
variable "nifi_key" {}
variable "landing_bucket" {}
variable "output_bucket" {}