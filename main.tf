terraform {
  backend "local" {}
}


provider "aws" {
  access_key                  = "test"
  region                      = "us-east-1"
  s3_force_path_style         = true
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    apigateway     = "http://localhost:4567"
    ec2   = "http://localhost:4566"
    cloudformation = "http://localhost:4581"
    cloudwatch     = "http://localhost:4582"
    dynamodb       = "http://localhost:4569"
    es             = "http://localhost:4578"
    firehose       = "http://localhost:4573"
    iam            = "http://localhost:4593"
    kinesis        = "http://localhost:4568"
    lambda         = "http://localhost:4574"
    route53        = "http://localhost:4580"
    redshift       = "http://localhost:4577"
    s3             = "http://localhost:4572"
    secretsmanager = "http://localhost:4584"
    ses            = "http://localhost:4579"
    sns            = "http://localhost:4575"
    sqs            = "http://localhost:4576"
    ssm            = "http://localhost:4583"
    stepfunctions  = "http://localhost:4585"
    sts            = "http://localhost:4592"
    autoscaling    = "http://localhost:4593"
 }
}

resource "aws_launch_configuration" "example" {
  image_id      = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF

}

resource "aws_security_group" "instance" {
    name = "terraform-example-instance"

    ingress {
        from_port   = var.server_port
        to_port     = var.server_port
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_autoscaling_group" "example" {
    launch_configuration = aws_launch_configuration.example.name
    vpc_zone_identifier = data.aws_subnet_ids.default.ids

    target_group_arns = [aws_lb_target_group.asg.arn]
    health_check_type = "ELB"

    min_size = 2
    max_size = 10

    tag {
        key = "Name"
        value = "terraform-asg-example"
        propagate_at_launch = true
    }

    lifecycle {
        create_before_destroy = true
    }
}

variable "server_port" {
    description = "The port the server will use to HTTP requests"
    type = number
    default = 8080
}

data "aws_vpc" "default" {
    default = true
}

data "aws_subnet_ids" "default" {
    vpc_id = data.aws_vpc.default.id
}

resource "aws_lb" "example" {
    name                = "terraform-asg-example"
    load_balancer_type  = "application"
    subnets             = data.aws_subnet_ids.default.ids
    security_groups     = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.example.arn
    port              = 80
    protocol          = "HTTP"

    # By default, return a simple 404 page
    default_action {
        type = "fixed-response"

        fixed_response {
            content_type = "text/plain"
            message_body = "404: page not found"
            status_code  = 404
        }
    }
}

resource "aws_security_group" "alb" {
    name = "terraform-example-alb"

    # Allow inbound HTTP requests
    ingress {
        from_port = 80
        to_port   = 80
        protocol  = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # Allow all outbound requests
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_lb_target_group" "asg" {
    name        = "terraform-asg-example"
    port        = var.server_port
    protocol    = "HTTP"
    vpc_id      = data.aws_vpc.default.id

    health_check {
        path                = "/"
        protocol            = "HTTP"
        matcher             = "200"
        interval            = 15
        timeout             = 3
        healthy_threshold   = 2
        unhealthy_threshold = 2
    }
}

resource "aws_lb_listener_rule" "asg" {
    listener_arn = aws_lb_listener.http.arn
    priority     = 100

    condition {
        path_pattern {
            values = ["*"]
        }
    }

    action {
        type                = "forward"
        target_group_arn    = aws_lb_target_group.asg.arn
    }
}

output "alb_dns_name" {
    value       = aws_lb.example.dns_name
    description = "The domain name of the load balancer"
}

