terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "ap-southeast-2"
  profile = "sandpit"
}

data "aws_availability_zones" "available" {}

locals {
  name    = "dms-migration"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Name       = local.name
  }
}

############################################################################
# DB SG and RDS
############################################################################
module "db_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = local.name
  description = "db security group"
  vpc_id      = module.vpc.vpc_id

  # ingress
  ingress_with_source_security_group_id = [
    {
      from_port   = 1433
      to_port     = 1433
      protocol    = "tcp"
      description = "Ingress from Bastion SG"
      source_security_group_id  = module.ec2-mssql-bastion.aws_security_group.id
    }  

  ]

  tags = local.tags
}
# module "rds" {
#   source = "terraform-aws-modules/rds/aws"

#   identifier = local.name

#   engine               = "sqlserver-ex"
#   engine_version       = "15.00"
#   family               = "sqlserver-ex-15.0" # DB parameter group
#   major_engine_version = "15.00"             # DB option group
#   instance_class       = "db.t3.small"

#   allocated_storage     = 20
#   max_allocated_storage = 100

#   # Encryption at rest is not available for DB instances running SQL Server Express Edition
#   storage_encrypted = false

#   username = "complete_mssql"
#   port     = 1433

#   multi_az               = false
#   db_subnet_group_name   = module.vpc.database_subnet_group
#   vpc_security_group_ids = [module.db_security_group.security_group_id]

#   maintenance_window              = "Mon:00:00-Mon:03:00"
#   backup_window                   = "03:00-06:00"
#   enabled_cloudwatch_logs_exports = ["error"]
#   create_cloudwatch_log_group     = true

#   backup_retention_period = 1
#   skip_final_snapshot     = true
#   deletion_protection     = false

#   options                   = []
#   create_db_parameter_group = false
#   license_model             = "license-included"
#   timezone                  = "GMT Standard Time"
#   character_set_name        = "Latin1_General_CI_AS"

#   tags = local.tags
# }

############################################################################
# Bastion SG and EC2
############################################################################
# module "bastion_security_group" {
#   source  = "terraform-aws-modules/security-group/aws"
#   version = "~> 4.0"

#   name        = local.name
#   description = "bastion host security group"
#   vpc_id      = module.vpc.vpc_id

#   # egress
#   egress_with_cidr_blocks = [
#     {
#       from_port   = 1433
#       to_port     = 1433
#       protocol    = "tcp"
#       description = "Egress out to mssql"
#       cidr_blocks = "0.0.0.0/0"
#     },
#     {
#       from_port   = 443
#       to_port     = 443
#       protocol    = "tcp"
#       description = "Egress to https"
#       cidr_blocks = "0.0.0.0/0"
#     }    

#   ]

#   tags = local.tags
# }

## SEE https://registry.terraform.io/modules/bayupw/ssm-vpc-endpoint/aws/latest

# Create IAM role and IAM instance profile for SSM
module "ssm_instance_profile" {
  source  = "bayupw/ssm-instance-profile/aws"
  version = "1.0.0"
}

# Create VPC Endpoints for SSM in private subnets
module "ssm_vpc_endpoint" {
  source  = "bayupw/ssm-vpc-endpoint/aws"
  version = "1.0.0"

  vpc_id         = module.vpc.vpc_id
  vpc_subnet_ids = module.vpc.database_subnets
}

# Launch EC2 instances in private subnet
module "ec2-mssql-bastion" {
  source  = "bayupw/amazon-linux-2/aws"
  version = "1.0.0"
  instance_hostname = "ec2-bastion"

  instance_type          = "t2.micro"

  vpc_id               = module.vpc.vpc_id
  subnet_id            = module.vpc.database_subnets[0]
  iam_instance_profile = module.ssm_instance_profile.aws_iam_instance_profile
}

############################################################################
# VPC
############################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.name
  cidr = local.vpc_cidr

  azs              = local.azs
  database_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 3)]

  create_database_subnet_group = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.tags
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = local.name
  description = "SQLServer Security Group"
  vpc_id      = module.vpc.vpc_id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 1433
      to_port     = 1433
      protocol    = "tcp"
      description = "SqlServer access from within VPC"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
  ]

  tags = local.tags
}