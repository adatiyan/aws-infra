
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
  count                   = local.no_of_subnets
  cidr_block              = cidrsubnet(aws_vpc.webapp_vpc.cidr_block, 8, count.index)
  vpc_id                  = aws_vpc.webapp_vpc.id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "public_subnet-${aws_vpc.webapp_vpc.id}-${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnet" {
  count             = local.no_of_subnets
  cidr_block        = cidrsubnet(aws_vpc.webapp_vpc.cidr_block, 8, (count.index + local.no_of_subnets))
  vpc_id            = aws_vpc.webapp_vpc.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "private_subnet-${aws_vpc.webapp_vpc.id}-${count.index + 1}"
  }
}

locals {
  no_of_subnets      = min(var.aws_subnet_count, length(data.aws_availability_zones.available.names))
  public_subnet_ids  = aws_subnet.public_subnet.*.id
  private_subnet_ids = aws_subnet.private_subnet.*.id
  timestamp          = formatdate("YYYY-MM-DDTHH-MM-SS", timestamp())
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = length(local.public_subnet_ids)
  subnet_id      = local.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_subnet_association" {
  count          = length(local.private_subnet_ids)
  subnet_id      = local.private_subnet_ids[count.index]
  route_table_id = aws_route_table.private_rt.id
}


# Define the security group resource
resource "aws_security_group" "app_sg" {
  name_prefix = "application"         # Set the name prefix for the security group
  vpc_id      = aws_vpc.webapp_vpc.id # Set the ID of the VPC to create the security group in

  # Define inbound rules
  ingress {
    from_port   = 22 # Allow SSH traffic
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow traffic from all IP addresses
  }

  ingress {
    from_port   = 443 # Allow SSH traffic
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow traffic from all IP addresses
  }

  ingress {
    from_port   = 80 # Allow HTTP traffic
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow traffic from all IP addresses
  }
  ingress {
    from_port   = 5080 # Allow HTTP traffic
    to_port     = 5080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow traffic from all IP addresses
  }


  egress {
    from_port   = 0 # Allow all outbound traffic
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Allow traffic to all IP addresses
  }

  tags = {
    Name = "ec2-sg-${timestamp()}" # Set the name tag for the security group
  }
}
resource "aws_instance" "webapp_instance" {
  ami                    = var.my_ami                     # Set the ID of the Amazon Machine Image to use
  instance_type          = "t2.micro"                     # Set the instance type
  key_name               = "ec2"                          # Set the key pair to use for SSH access
  vpc_security_group_ids = [aws_security_group.app_sg.id] # Set the security group to attach to the instance
  subnet_id              = local.public_subnet_ids[0]     # Set the ID of the subnet to launch the instance in
  # Enable protection against accidental termination
  disable_api_termination = false
  # Set the root volume size and type
  root_block_device {
    volume_size           = 20    # Replace with your preferred root volume size (in GB)
    volume_type           = "gp2" # Replace with your preferred root volume type (e.g. "gp2", "io1", etc.)
    delete_on_termination = true
  }
  depends_on           = [aws_db_instance.rds_instance]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  /*user_data            = <<EOF
  #!/bin/bash
  echo "[Unit]
  Description=Webapp Service
  ServiceAfter=syslog.target

  [Service]
  Environment="DB_HOST=${aws_db_instance.rds_instance.endpoint}"
  Environment="DB_USER=${aws_db_instance.rds_instance.username}"
  Environment="DB_PASSWORD=${aws_db_instance.rds_instance.password}"
  Environment="DB_DATABASE=${aws_db_instance.rds_instance.db_name}"
  Environment="AWS_BUCKET_NAME=${aws_s3_bucket.s3_bucket.bucket}"
  User=root
  ExecStart=/usr/bin/java -jar home/ec2-user/webapp-0.0.1-SNAPSHOT.jar
  SuccessExitStatus=143
  Restart=always
  RestartSec=5

  [Install]
  WantedBy=multi-user.target" > /etc/systemd/system/webservice.service

  server.port=5080
  spring.datasource.url="jdbc:mysql://${aws_db_instance.rds_instance.endpoint}/${aws_db_instance.rds_instance.db_name}"
  spring.datasource.username=${aws_db_instance.rds_instance.username}
  spring.datasource.password=${aws_db_instance.rds_instance.password}
  spring.jpa.hibernate.ddl-auto=update
  aws.s3.bucketName=${aws_s3_bucket.s3_bucket.bucket} > /home/ec2-user/application.properties

  sudo systemctl daemon-reload
  sudo systemctl start webservice.service
  sudo systemctl enable webservice.service
  EOF*/
  tags = {
    Name = "webapp-instance-${timestamp()}" # Set the name tag for the instance
  }
}

# Database security group
resource "aws_security_group" "db_sg" {
  name        = "database"
  description = "Security group for RDS instance for database"
  vpc_id      = aws_vpc.webapp_vpc.id
  ingress {
    protocol        = "tcp"
    from_port       = "3306"
    to_port         = "3306"
    security_groups = [aws_security_group.app_sg.id]
  }
  tags = {
    "Name" = "database-sg-${timestamp()}"
  }
}

#s3 bucket
resource "aws_s3_bucket" "s3_bucket" {
  lifecycle_rule {
    id      = "StorageTransitionRule"
    enabled = true
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    "Name" = "s3_bucket-${timestamp()}"
  }
}

#iam role for ec2
resource "aws_iam_role" "ec2_role" {
  description        = "Policy for EC2 instance"
  name               = "tf-ec2-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      }
    }
  ]
}
EOF
  tags = {
    "Name" = "ec2-iam-role"
  }
}

#policy document
data "aws_iam_policy_document" "policy_document" {
  version = "2012-10-17"
  statement {
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "${aws_s3_bucket.s3_bucket.arn}",
      "${aws_s3_bucket.s3_bucket.arn}/*"
    ]
  }
  depends_on = [aws_s3_bucket.s3_bucket]
}

#iam policy for role
resource "aws_iam_role_policy" "s3_policy" {
  name       = "tf-s3-policy"
  role       = aws_iam_role.ec2_role.id
  policy     = data.aws_iam_policy_document.policy_document.json
  depends_on = [aws_s3_bucket.s3_bucket]
}

resource "aws_db_subnet_group" "db_subnet_group" {
  description = "Private Subnet group for RDS"
  subnet_ids  = ([local.private_subnet_ids[0], local.private_subnet_ids[1], local.private_subnet_ids[2]])
  tags = {
    "Name" = "db-subnet-group"
  }
}

resource "aws_db_instance" "rds_instance" {
  allocated_storage      = var.db_storage_size
  identifier             = "app-rds-db"
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  instance_class         = var.db_instance_class
  engine                 = var.db_engine
  engine_version         = var.db_engine_version
  //multi_az               = false
  name                = var.db_name
  username            = var.db_username
  password            = var.db_password
  publicly_accessible = var.db_public_access
  multi_az            = var.db_multiaz
  skip_final_snapshot = true
  tags = {
    "Name" = "rds-${timestamp()}"
  }
}


#iam instance profile for ec2
resource "aws_iam_instance_profile" "ec2_profile" {
  role = aws_iam_role.ec2_role.name
}
