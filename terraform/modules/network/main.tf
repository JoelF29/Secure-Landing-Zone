# Module réseau — Zero Trust networking (TON EDGE : exploite ta spé réseau/télécom).
# Skeleton à compléter. Les commentaires indiquent les décisions de sécurité attendues.

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${aws_vpc.this.id}/flow-logs"
  retention_in_days = 30
  tags = {
    Name        = "${var.environment}-vpc-flow-logs"
    Environment = var.environment
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${var.environment}-vpc-flow-logs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  log_destination_type = "cloud-watch-logs"
  iam_role_arn         = aws_iam_role.vpc_flow_logs.arn
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
}

output "vpc_id" {
  value = aws_vpc.this.id
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = {
    Name        = "${var.environment}-${each.value.tier}-${each.value.az}"
    Environment = var.environment
    Tier        = each.value.tier
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${var.environment}-igw"
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${var.environment}-public-rt"
    Environment = var.environment
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "${var.environment}-nat-eip"
    Environment = var.environment
  }
}

resource "aws_nat_gateway" "this" {

  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.this["public-${var.azs[0]}"].id
  depends_on    = [aws_internet_gateway.this]

  tags = {
    Name        = "${var.environment}-nat-${var.azs[0]}"
    Environment = var.environment
  }
}

resource "aws_route" "public_to_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${var.environment}-app-rt"
    Environment = var.environment
  }
}

resource "aws_route" "app_to_nat" {
  route_table_id         = aws_route_table.app.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${var.environment}-data-rt"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  for_each = { for k, v in local.subnets : k => v if v.tier == "public" }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "app" {
  for_each = { for k, v in local.subnets : k => v if v.tier == "app" }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.app.id
}

resource "aws_route_table_association" "data" {
  for_each = { for k, v in local.subnets : k => v if v.tier == "data" }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.data.id
}
