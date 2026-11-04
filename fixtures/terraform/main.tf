terraform {
  required_version = ">= 1.5"
}

variable "name" {
  type    = string
  default = "ci-fixture"
}

# terraform_data is built in, so init needs no provider download.
resource "terraform_data" "example" {
  input = var.name
}

output "example_id" {
  value = terraform_data.example.id
}
