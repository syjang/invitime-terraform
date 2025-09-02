variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "alb_sg_id" { type = string }
variable "certificate_arn" { type = string }
variable "web_port" { 
    type = number
 default = 3000 
 }
variable "api_port" { 
    type = number
 default = 8000
}
variable "web_host_headers" {
  type    = list(string)
  default = []
}
variable "api_host_headers" {
  type    = list(string)
  default = []
}

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "web" {
  name     = "${var.name_prefix}-web-tg"
  port     = var.web_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  target_type = "ip"
  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }
}

resource "aws_lb_target_group" "api" {
  name     = "${var.name_prefix}-api-tg"
  port     = var.api_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  target_type = "ip"
  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_listener_rule" "web_host" {
  count        = length(var.web_host_headers) > 0 ? 1 : 0
  listener_arn = aws_lb_listener.https.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
  condition {
    host_header {
      values = var.web_host_headers
    }
  }
}

resource "aws_lb_listener_rule" "api_host" {
  count        = length(var.api_host_headers) > 0 ? 1 : 0
  listener_arn = aws_lb_listener.https.arn
  priority     = 20
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
  condition {
    host_header {
      values = var.api_host_headers
    }
  }
}

output "alb_arn" { value = aws_lb.this.arn }
output "alb_dns_name" { value = aws_lb.this.dns_name }
output "tg_web_arn" { value = aws_lb_target_group.web.arn }
output "tg_api_arn" { value = aws_lb_target_group.api.arn }
output "alb_zone_id" { value = aws_lb.this.zone_id }

