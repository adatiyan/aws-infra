
# Create a VPC
resource "aws_vpc" "webapp_vpc" {
  cidr_block = var.cidr_name
  tags = {
    Name = var.vpc_tag_name
  }
}
# Create a IG
resource "aws_internet_gateway" "webapp_igw" {
  vpc_id = aws_vpc.webapp_vpc.id
}

data "aws_availability_zones" "available" {
  state = "available"
}
output "availability_zones" {
  value = data.aws_availability_zones.available.names
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.webapp_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.webapp_igw.id
  }
  tags = {
    Name = "public_route_table-${aws_vpc.webapp_vpc.id}"
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.webapp_vpc.id
  tags = {
    Name = "private_route_table-${aws_vpc.webapp_vpc.id}"
  }
}


# resource "aws_route" "public_rt_internet_gateway" {
#   route_table_id = aws_route_table.public_rt.id
#   cidr_block = "0.0.0.0/0"
#   gateway_id = aws_internet_gateway.webapp_igw.id
# }


resource "aws_subnet" "public_subnet" {
  count             = local.no_of_subnets
  cidr_block        = cidrsubnet(aws_vpc.webapp_vpc.cidr_block, 8, count.index)
  vpc_id            = aws_vpc.webapp_vpc.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
   tags = {
    Name = "public_subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnet" {
  count             = local.no_of_subnets
  cidr_block        = cidrsubnet(aws_vpc.webapp_vpc.cidr_block, 8, count.index + local.no_of_subnets))
  vpc_id            = aws_vpc.webapp_vpc.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
    tags = {
    Name = "private_subnet-${count.index + 1}"
  }
}

locals {
  no_of_subnets = min(var.aws_subnet_count, length(data.aws_availability_zones.available.names))
  public_subnet_ids = aws_subnet.public_subnet.*.id
  private_subnet_ids = aws_subnet.private_subnet.*.id
}

resource "aws_route_table_association" "public_subnet_association" {
  count = length(local.public_subnet_ids)
  subnet_id = local.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_subnet_association" {
  count = length(local.private_subnet_ids)
  subnet_id = local.private_subnet_ids[count.index]
  route_table_id = aws_route_table.private_rt.id
}


