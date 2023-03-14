variable "vpc_id" {
    type = string
}

variable "subnet_ids" {
    type = list(string)
}

variable "key_name" {
    type = string
}

variable "number_of_clients" {
  default = 4
}

variable "number_of_servers" {
  default = 1
}

variable "port" {
  default = 4711
}

variable "protocol" {
  default = "UDP"
}

data "aws_ssm_parameter" "amazon-linux-ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

locals {
  #  x        = jsondecode(data.aws_ssm_parameter.amazon-linux-ami.value)
  #  image_id = local.x["image_id"]
  image_id = data.aws_ssm_parameter.amazon-linux-ami.value
}

resource "aws_launch_template" "default" {
  name_prefix   = "nlb-test"
  image_id      = local.image_id
  instance_type = "t2.nano"
  key_name      = var.key_name
  user_data     = base64encode("yum install nc httpd tcpdump && systemctl start httpd")
}

resource "aws_autoscaling_group" "client" {
  name                = "nlb-test-client"
  desired_capacity    = var.number_of_clients
  max_size            = var.number_of_clients
  min_size            = var.number_of_clients
  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.default.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "nlb-test-client"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "server" {
  name                = "nlb-test-server"
  desired_capacity    = var.number_of_servers
  max_size            = var.number_of_servers
  min_size            = var.number_of_servers
  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = [aws_lb_target_group.default.arn]

  launch_template {
    id      = aws_launch_template.default.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "nlb-test-server"
    propagate_at_launch = true
  }
}

resource "aws_lb_target_group" "default" {
  name     = "nlb-test"
  port     = var.port
  protocol = var.protocol
  vpc_id   = var.vpc_id

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = 22
  }

  stickiness {
    enabled = true
    type    = "source_ip"
  }
}

resource "aws_lb" "default" {
  name               = "nlb-test"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  enable_deletion_protection = false

  enable_cross_zone_load_balancing = true
}

resource "aws_alb_listener" "default" {
  load_balancer_arn = aws_lb.default.arn
  port              = var.port
  protocol          = var.protocol

  default_action {
    target_group_arn = aws_lb_target_group.default.arn
    type             = "forward"
  }
}
