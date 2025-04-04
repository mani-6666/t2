variable "aws_region" {
  default = "us-east-1"
}

variable "medusa_image" {
  default = "medusajs/medusa:latest"
}

variable "jwt_secret" {}
variable "db_user" {
  default = "medusauser"
}
variable "db_password" {}
