variable "repository_name" {
  type = string
}
variable "image_mutability" {
  type    = string
  default = "MUTABLE"
}
variable "scan_on_push" {
  type    = bool
  default = true
}

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
}

output "repository_url" { value = aws_ecr_repository.this.repository_url }
output "repository_arn" { value = aws_ecr_repository.this.arn }
output "repository_name" { value = aws_ecr_repository.this.name }

