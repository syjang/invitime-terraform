variable "name" { type = string }
variable "cluster_arn" { type = string }
variable "task_cpu" {
  type    = number
  default = 256
}
variable "task_memory" {
  type    = number
  default = 512
}
variable "container_image" { type = string }
variable "container_port" { type = number }
variable "desired_count" {
  type    = number
  default = 1
}
variable "assign_public_ip" {
  type    = bool
  default = true
}
variable "subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "environment" {
  type    = map(string)
  default = {}
}

variable "log_group_name" {
  description = "Custom CloudWatch Logs group name. Defaults to /ecs/<service-name> if null"
  type        = string
  default     = null
}
variable "target_group_arn" {
  type    = string
  default = null
}
variable "secrets" {
  description = "List of secrets to inject into container env (name/valueFrom)"
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}
variable "secrets_manager_arns" {
  description = "Secrets Manager ARNs the task execution role can read"
  type        = list(string)
  default     = []
}
variable "secret_json_map" {
  description = "Map of env name -> { secret_arn, key } to build valueFrom automatically"
  type = map(object({
    secret_arn = string
    key        = string
  }))
  default = {}
}

variable "task_policy_json" {
  description = "Optional IAM policy JSON attached to the task role (e.g., S3/SES)"
  type        = string
  default     = null
}

variable "manage_task_definition" {
  description = "Whether this module should create/manage the task definition"
  type        = bool
  default     = true
}

variable "task_family" {
  description = "Task definition family to reference when manage_task_definition=false"
  type        = string
  default     = null
}

locals {
  computed_secrets = concat(
    var.secrets,
    [for name, cfg in var.secret_json_map : {
      name      = name
      valueFrom = "${cfg.secret_arn}:${cfg.key}::"
    }]
  )

  secret_arns_from_map = [for _, cfg in var.secret_json_map : cfg.secret_arn]
  all_secret_arns      = distinct(concat(var.secrets_manager_arns, local.secret_arns_from_map))

  log_group_name = var.log_group_name != null ? var.log_group_name : "/ecs/${var.name}"
}

resource "aws_iam_role" "task_execution" {
  name = "${var.name}-task-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_iam_policy" "secrets_access" {
  name  = "${var.name}-secrets-access"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = ["secretsmanager:GetSecretValue"],
      Resource = [
        "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_access" {
  role       = aws_iam_role.task_execution.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

resource "aws_iam_role" "task_role" {
  name = "${var.name}-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "task_inline" {
  count  = var.task_policy_json == null ? 0 : 1
  name   = "${var.name}-task-policy"
  policy = var.task_policy_json
}

resource "aws_iam_role_policy_attachment" "task_inline" {
  count      = var.task_policy_json == null ? 0 : 1
  role       = aws_iam_role.task_role.name
  policy_arn = aws_iam_policy.task_inline[0].arn
}

resource "aws_ecs_task_definition" "this" {
  count                    = var.manage_task_definition ? 1 : 0
  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = var.name
      image     = var.container_image
      essential = true
      portMappings = [{
        containerPort = var.container_port
        hostPort      = var.container_port
        protocol      = "tcp"
      }]
      environment = [for k, v in var.environment : { name = k, value = v }]
      secrets      = local.computed_secrets
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = local.log_group_name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

data "aws_ecs_task_definition" "latest" {
  count           = var.manage_task_definition ? 0 : 1
  task_definition = coalesce(var.task_family, var.name)
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = 14
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_arn
  task_definition = var.manage_task_definition ? aws_ecs_task_definition.this[0].arn : data.aws_ecs_task_definition.latest[0].arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.subnet_ids
    security_groups = var.security_group_ids
    assign_public_ip = var.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [var.target_group_arn]
    content {
      target_group_arn = load_balancer.value
      container_name   = var.name
      container_port   = var.container_port
    }
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

output "service_name" { value = aws_ecs_service.this.name }
output "task_definition_arn" {
  value = var.manage_task_definition ? aws_ecs_task_definition.this[0].arn : data.aws_ecs_task_definition.latest[0].arn
}

