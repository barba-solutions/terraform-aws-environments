variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "project" {
  type    = string
  default = "barba-demo"
}

variable "instance_type" {
  type = string
}

variable "bucket_force_destroy" {
  type = bool
}

variable "ec2_termination_protection" {
  type = bool
}

variable "detailed_monitoring" {
  type = bool
}
