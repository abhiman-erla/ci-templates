terraform {
  required_version = ">= 1.5"
}

resource "terraform_data" "example" {
  input = "ci-fixture"
}

# Planted defect: terraform_data.missing is never declared, so validate must fail.
output "missing_id" {
  value = terraform_data.missing.id
}
