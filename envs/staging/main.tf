provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = "staging"
      Repo        = "terraform-aws-environments"
    }
  }
}

module "app" {
  source = "../../modules/app-stack"

  project                    = var.project
  environment                = "staging"
  instance_type              = var.instance_type
  bucket_force_destroy       = var.bucket_force_destroy
  ec2_termination_protection = var.ec2_termination_protection
  detailed_monitoring        = var.detailed_monitoring
}
