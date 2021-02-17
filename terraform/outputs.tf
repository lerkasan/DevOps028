output "demo2_elb_public_dns" {
  value = aws_elb.demo2_elb.dns_name
}

output "demo2_rds_endpoint" {
  value = aws_db_instance.demo2_rds.endpoint
}
