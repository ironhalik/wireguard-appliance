##
## Variables
##
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_enable_dns_support" {
  description = "Enable DNS support"
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames"
  type        = bool
  default     = true
}

variable "vpc_public_subnets" {
  description = "List of public subnets"
  type        = list(string)
  default = [
    "10.0.0.0/24"
  ]
}


##
## Resources
##
data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  enable_dns_support   = var.vpc_enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = {
    "Name" = "shared_main"
  }
}

resource "aws_subnet" "public" {
  for_each = { for i, cidr in var.vpc_public_subnets : data.aws_availability_zones.available.names[i] => cidr }

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = {
    "Name" = "${var.project_name}_public_${each.key}"
  }
}

resource "aws_internet_gateway" "public" {
  count = length(var.vpc_public_subnets) > 0 ? 1 : 0

  vpc_id = aws_vpc.main.id

  tags = {
    "Name" = "${var.project_name}_main"
  }
}


resource "aws_route_table" "public" {
  count = length(var.vpc_public_subnets) > 0 ? 1 : 0

  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.public[0].id
  }

  tags = {
    "Name" = "${var.project_name}_main"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public[0].id
}
