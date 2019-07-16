provider "aws" {
  region = "us-east-1"
}

resource "random_id" "project_name"{
  byte_length = 4
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  name = "${random_id.project_name.hex}"

  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  assign_generated_ipv6_cidr_block = true

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    Name = "overridden-name-public"
  }

  tags = {
    Owner       = "cmatteson"
    Environment = "dev"
  }

  vpc_tags = {
    Name = "${random_id.project_name.hex}-vpc"
  }
}

module "consul-aws" {
  source = "../"
  cluster_name = random_id.project_name.hex
  instance_type = "t2.small"
  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets
  ssh_key_name = "chrismatteson-us-east-1"
  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
  allowed_ssh_cidr_blocks = ["0.0.0.0/0"]
  consul_version = "1.5.2+ent"
  server = true
}
