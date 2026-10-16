# own state per env. change "barba" to your prefix (same one used in bootstrap)
terraform {
  backend "s3" {
    bucket       = "barba-tfstate-dev"
    key          = "app-stack/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
