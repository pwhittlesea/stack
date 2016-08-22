/**
 * The worker module creates an ECS service that has no ELB attached.
 *
 * Usage:
 *
 *     module "my_worker" {
 *       source       = "github.com/segmentio/stack"
 *       environment  = "prod"
 *       name         = "worker"
 *       image        = "worker"
 *       cluster      = "default"
 *     }
 *
 */

/**
 * Required Variables.
 */

variable "environment" {
  description = "Environment tag, e.g prod"
}

variable "image" {
  description = "The docker image name, e.g nginx"
}

variable "name" {
  description = "The worker name, if empty the service name is defaulted to the image name"
  default     = ""
}

variable "version" {
  description = "The docker image version"
  default     = "latest"
}

variable "cluster" {
  description = "The cluster name or ARN"
}

/**
 * Options.
 */

variable "command" {
  description = "The raw json of the task command"
  default     = "[]"
}

variable "env_vars" {
  description = "The raw json of the task env vars"
  default     = "[]"
}

variable "log_conf" {
  description = "The raw json of the task logging configuration"
  default     = "{}"
}

variable "desired_count" {
  description = "The desired count"
  default     = 1
}

variable "memory" {
  description = "The number of MiB of memory to reserve for the container"
  default     = 512
}

variable "cpu" {
  description = "The number of cpu units to reserve for the container"
  default     = 512
}

/**
 * Resources.
 */

resource "aws_ecs_service" "main" {
  name            = "${module.task.name}"
  cluster         = "${var.cluster}"
  task_definition = "${module.task.arn}"
  desired_count   = "${var.desired_count}"

  lifecycle {
    create_before_destroy = true
  }
}

module "task" {
  source = "../task"

  name          = "${coalesce(var.name, var.image)}"
  image         = "${var.image}"
  image_version = "${var.version}"
  command       = "${var.command}"
  env_vars      = "${var.env_vars}"
  memory        = "${var.memory}"
  cpu           = "${var.cpu}"
  log_conf      = "${var.log_conf}"
}
