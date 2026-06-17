output "vpc_id" {
  value = aws_vpc.this.id
}

output "app_subnet_ids" {
  value = [for k, v in aws_subnet.this : v.id if local.subnets[k].tier == "app"]

}

output "data_subnet_ids" {
  value = [for k, v in aws_subnet.this : v.id if local.subnets[k].tier == "data"]
}

output "public_subnet_ids" {
  value = [for k, v in aws_subnet.this : v.id if local.subnets[k].tier   == "public"]
}

output "app_sg_id" {
  value = aws_security_group.app.id
}

output "data_sg_id" {
  value = aws_security_group.data.id
}

output "public_sg_id" {
  value = aws_security_group.public.id
}
