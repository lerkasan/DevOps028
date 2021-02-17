provider "aws" {
  region = var.aws_region
}

# Create SSM parameters with bucket name and RDS identifier. Parameters will be used at userdata script of autoscaling group launch configuration
resource "aws_ssm_parameter" "demo2_bucket_name_param" {
  name      = "demo2_bucket_name"
  type      = "String"
  value     = var.bucket_name
  overwrite = "true"
}

resource "aws_ssm_parameter" "demo2_rds_identifier_param" {
  name      = "demo2_rds_identifier"
  type      = "String"
  value     = var.rds_identifier
  overwrite = "true"
}

resource "aws_db_instance" "demo2_rds" {
  name                    = "demo2_rds"
  depends_on              = [aws_security_group.demo2_rds_secgroup]
  identifier              = var.rds_identifier
  allocated_storage       = var.db_storage_size
  storage_type            = "gp2"
  instance_class          = var.db_instance_class
  engine                  = var.db_engine
  engine_version          = var.db_engine_version
  port                    = var.db_port
  backup_retention_period = "0"
//  name                    = var.db_name
  username                = var.db_user
  password                = var.db_pass
  publicly_accessible     = "false"
  vpc_security_group_ids  = [aws_security_group.demo2_rds_secgroup.id]
  db_subnet_group_name    = aws_db_subnet_group.demo2_db_subnet_group.id
  skip_final_snapshot     = "true"

  provisioner "local-exec" {
    command = "./populate-database.sh"
  }
}

resource "aws_elb" "demo2_elb" {
  name                = var.elb_name
  subnets             = [aws_subnet.demo2_subnet1.id, aws_subnet.demo2_subnet2.id, aws_subnet.demo2_subnet3.id]
  security_groups     = [aws_security_group.demo2_elb_secgroup.id]
  listener {
    instance_port     = var.webapp_port
    instance_protocol = "http"
    lb_port           = var.webapp_port
    lb_protocol       = "http"
  }
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    target              = "HTTP:${var.webapp_port}${var.health_check_path}"
    interval            = 15
  }
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 600
}

resource "aws_lb_cookie_stickiness_policy" "default" {
  name                     = "lb-cookie-stickiness-policy"
  load_balancer            = aws_elb.demo2_elb.id
  lb_port                  = var.webapp_port
  cookie_expiration_period = 600
}

resource "aws_launch_configuration" "demo2_launch_configuration" {
  name                  = "demo2_launch_configuration"
  depends_on            = [aws_security_group.demo2_webapp_secgroup]
  image_id              = var.ec2_ami
  instance_type         = var.ec2_instance_type
  security_groups       = [aws_security_group.demo2_webapp_secgroup.id]
  user_data             = file("./userdata.sh")
  key_name              = var.ssh_key_name
  iam_instance_profile  = var.iam_profile # IAM role for ec2 instances in launch configuration. Role gives read only permissions to S3, RDS, SSM
  enable_monitoring     = "false"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "demo2_autoscalegroup" {
  name                 = var.autoscalegroup_name
# Depends on is added to check that SSM parameters used in launch configuration userdata are created before userdata executing
  depends_on = [aws_ssm_parameter.demo2_bucket_name_param, aws_ssm_parameter.demo2_rds_identifier_param]
  max_size             = var.max_servers_in_autoscaling_group
  min_size             = var.min_servers_in_autoscaling_group
  desired_capacity     = var.desired_servers_in_autoscaling_group
  launch_configuration = aws_launch_configuration.demo2_launch_configuration.name
  health_check_type    = "ELB"
# Alternative to attaching load balancers here is using resource "aws_autoscaling_attachment"
  load_balancers       = [aws_elb.demo2_elb.name]
  vpc_zone_identifier  = [aws_subnet.demo2_subnet1.id, aws_subnet.demo2_subnet2.id, aws_subnet.demo2_subnet3.id]
  termination_policies = ["OldestInstance"]

  lifecycle {
    create_before_destroy = true
  }
  # Sleep to give Spring Boot application (in userdata of launch configuration) time to properly start
  provisioner "local-exec" {
    command = "sleep 30"
  }
  tag {
    key                 = "Name"
    value               = "webapp"
    propagate_at_launch = "true"
  }
}

# Attach classic load balancer to autoscaling group here can be used instead of using parameter load_balancers at resource "aws_autoscaling_group"
# resource "aws_autoscaling_attachment" "asg_attachment_bar" {
#   depends_on             = [aws_autoscaling_group.demo2_autoscalegroup]
#   autoscaling_group_name = aws_autoscaling_group.demo2_autoscalegroup.id
#   elb                    = aws_elb.demo2_elb.id
# }
