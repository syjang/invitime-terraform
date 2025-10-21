variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "allowed_ingress_sg_ids" { type = list(string) }

variable "engine_version" {
  type    = string
  default = "8.4.6"
}
variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}
variable "allocated_storage" {
  type    = number
  default = 20
}
variable "multi_az" {
  type    = bool
  default = false
}
variable "deletion_protection" {
  type    = bool
  default = false
}
variable "backup_retention" {
  type    = number
  default = 1
}

variable "db_name" { type = string }
variable "db_username" {
  type    = string
  default = "appuser"
}

variable "publicly_accessible" {
  type        = bool
  default     = false
}

variable "allowed_cidr_ingress" {
  description = "Optional list of CIDR blocks allowed to access MySQL (3306). Use cautiously (e.g., [\"1.2.3.4/32\"])."
  type        = list(string)
  default     = []
}

resource "random_password" "db" {
  length  = 20
  special = true
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "RDS MySQL SG"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = var.allowed_ingress_sg_ids
  }
  dynamic "ingress" {
    for_each = var.allowed_cidr_ingress
    content {
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "this" {
  identifier              = "${var.name_prefix}-mysql"
  engine                  = "mysql"
  engine_version          = var.engine_version
  instance_class          = var.instance_class
  allocated_storage       = var.allocated_storage
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  username                = var.db_username
  password                = random_password.db.result
  db_name                 = var.db_name
  multi_az                = var.multi_az
  deletion_protection     = var.deletion_protection
  backup_retention_period = var.backup_retention
  publicly_accessible     = var.publicly_accessible
  skip_final_snapshot     = true
  storage_encrypted       = true
  apply_immediately       = true

  lifecycle {
    ignore_changes = [
      db_subnet_group_name,
      publicly_accessible
    ]
  }
}

resource "aws_secretsmanager_secret" "db" {
  name = "${var.name_prefix}-db-credentials"
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username,
    password = random_password.db.result,
    host     = aws_db_instance.this.address,
    port     = tostring(aws_db_instance.this.port),
    dbname   = var.db_name
  })
}

output "endpoint" { value = aws_db_instance.this.address }
output "port" { value = aws_db_instance.this.port }
output "security_group_id" { value = aws_security_group.rds.id }
output "secret_arn" { value = aws_secretsmanager_secret.db.arn }

