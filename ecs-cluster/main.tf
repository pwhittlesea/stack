/**
 * ECS Cluster creates a cluster with the following features:
 *
 *  - Autoscaling groups
 *  - Instance tags for filtering
 *  - EBS volume for docker resources
 *
 *
 * Usage:
 *
 *      module "cdn" {
 *        source               = "github.com/segmentio/stack/ecs-cluster"
 *        environment          = "prod"
 *        name                 = "cdn"
 *        vpc_id               = "vpc-id"
 *        image_id             = "ami-id"
 *        subnet_ids           = "1,2"
 *        key_name             = "ssh-key"
 *        security_groups      = "1,2"
 *        iam_instance_profile = "id"
 *        region               = "us-west-2"
 *        availability_zones   = "a,b"
 *        instance_type        = "t2.small"
 *      }
 *
 */

variable "name" {
  description = "The cluster name, e.g cdn"
}

variable "environment" {
  description = "Environment tag, e.g prod"
}

variable "vpc_id" {
  description = "VPC ID"
}

variable "image_id" {
  description = "AMI Image ID"
}

variable "subnet_ids" {
  description = "Comma separated list of subnet IDs"
}

variable "key_name" {
  description = "SSH key name to use"
}

variable "security_groups" {
  description = "Comma separated list of security groups"
}

variable "iam_instance_profile" {
  description = "Instance profile ARN to use in the launch configuration"
}

variable "region" {
  description = "AWS Region"
}

variable "availability_zones" {
  description = "Comma separated list of AZs"
}

variable "instance_type" {
  description = "The instance type to use, e.g t2.small"
}

variable "instance_ebs_optimized" {
  description = "When set to true the instance will be launched with EBS optimized turned on"
  default     = true
}

variable "min_size" {
  description = "Minimum instance count"
  default     = 3
}

variable "max_size" {
  description = "Maxmimum instance count"
  default     = 100
}

variable "desired_capacity" {
  description = "Desired instance count"
  default     = 3
}

variable "associate_public_ip_address" {
  description = "Should created instances be publicly accessible (if the SG allows)"
  default = false
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  default     = 25
}

variable "docker_volume_size" {
  description = "Attached EBS volume size in GB"
  default     = 25
}

variable "docker_auth_type" {
  description = "The docker auth type, see https://godoc.org/github.com/aws/amazon-ecs-agent/agent/engine/dockerauth for the possible values"
  default     = ""
}

variable "docker_auth_data" {
  description = "A JSON object providing the docker auth data, see https://godoc.org/github.com/aws/amazon-ecs-agent/agent/engine/dockerauth for the supported formats"
  default     = ""
}

variable "ami_start_command" {
  description = "A custom command that can be run on all created cluster instances. This could be used to call a custom start script baked into the AMI. E.g. '/opt/start.sh'"
  default     = "echo 'Startup Script Complete'"
}

resource "aws_security_group" "cluster" {
  name        = "${var.name}-ecs-cluster"
  vpc_id      = "${var.vpc_id}"
  description = "Allows traffic from and to the EC2 instances of the ${var.name} ECS cluster"

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = -1
    security_groups = ["${split(",", var.security_groups)}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name        = "ECS cluster (${var.name})"
    Environment = "${var.environment}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ecs_cluster" "main" {
  name = "${var.name}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "template_file" "cloud_config" {
  template = "${file("${path.module}/files/cloud-config.yml.tpl")}"

  vars {
    environment       = "${var.environment}"
    name              = "${var.name}"
    region            = "${var.region}"
    docker_auth_type  = "${var.docker_auth_type}"
    docker_auth_data  = "${var.docker_auth_data}"
    ami_start_command = "${var.ami_start_command}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_configuration" "main" {
  name_prefix = "${format("%s-", var.name)}"

  image_id                    = "${var.image_id}"
  instance_type               = "${var.instance_type}"
  ebs_optimized               = "${var.instance_ebs_optimized}"
  iam_instance_profile        = "${var.iam_instance_profile}"
  key_name                    = "${var.key_name}"
  security_groups             = ["${aws_security_group.cluster.id}"]
  user_data                   = "${template_file.cloud_config.rendered}"
  associate_public_ip_address = "${var.associate_public_ip_address}"

  # root
  root_block_device {
    volume_type = "gp2"
    volume_size = "${var.root_volume_size}"
  }

  # docker
  ebs_block_device {
    device_name = "/dev/xvdcz"
    volume_type = "gp2"
    volume_size = "${var.docker_volume_size}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "main" {
  name = "${var.name}"

  availability_zones   = ["${split(",", var.availability_zones)}"]
  vpc_zone_identifier  = ["${split(",", var.subnet_ids)}"]
  launch_configuration = "${aws_launch_configuration.main.id}"
  min_size             = "${var.min_size}"
  max_size             = "${var.max_size}"
  desired_capacity     = "${var.desired_capacity}"
  termination_policies = ["OldestLaunchConfiguration", "Default"]

  tag {
    key                 = "Name"
    value               = "${var.name}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Cluster"
    value               = "${var.name}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "${var.environment}"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.name}-scaleup"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = "${aws_autoscaling_group.main.name}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.name}-scaledown"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = "${aws_autoscaling_group.main.name}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name}-cpureservation-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUReservation"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "90"

  dimensions {
    ClusterName = "${aws_ecs_cluster.main.name}"
  }

  alarm_description = "Scale up if the cpu reservation is above 90% for 10 minutes"
  alarm_actions     = ["${aws_autoscaling_policy.scale_up.arn}"]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "${var.name}-memoryreservation-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryReservation"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "90"

  dimensions {
    ClusterName = "${aws_ecs_cluster.main.name}"
  }

  alarm_description = "Scale up if the memory reservation is above 90% for 10 minutes"
  alarm_actions     = ["${aws_autoscaling_policy.scale_up.arn}"]

  lifecycle {
    create_before_destroy = true
  }

  # This is required to make cloudwatch alarms creation sequential, AWS doesn't
  # support modifying alarms concurrently.
  depends_on = ["aws_cloudwatch_metric_alarm.cpu_high"]
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.name}-cpureservation-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUReservation"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "10"

  dimensions {
    ClusterName = "${aws_ecs_cluster.main.name}"
  }

  alarm_description = "Scale down if the cpu reservation is below 10% for 10 minutes"
  alarm_actions     = ["${aws_autoscaling_policy.scale_down.arn}"]

  lifecycle {
    create_before_destroy = true
  }

  # This is required to make cloudwatch alarms creation sequential, AWS doesn't
  # support modifying alarms concurrently.
  depends_on = ["aws_cloudwatch_metric_alarm.memory_high"]
}

resource "aws_cloudwatch_metric_alarm" "memory_low" {
  alarm_name          = "${var.name}-memoryreservation-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryReservation"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "10"

  dimensions {
    ClusterName = "${aws_ecs_cluster.main.name}"
  }

  alarm_description = "Scale down if the memory reservation is below 10% for 10 minutes"
  alarm_actions     = ["${aws_autoscaling_policy.scale_down.arn}"]

  lifecycle {
    create_before_destroy = true
  }

  # This is required to make cloudwatch alarms creation sequential, AWS doesn't
  # support modifying alarms concurrently.
  depends_on = ["aws_cloudwatch_metric_alarm.cpu_low"]
}

// The cluster name, e.g cdn
output "name" {
  value = "${var.name}"
}

// The cluster security group ID.
output "security_group_id" {
  value = "${aws_security_group.cluster.id}"
}
