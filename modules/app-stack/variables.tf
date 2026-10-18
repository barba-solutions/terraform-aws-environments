variable "project" {
  description = "name prefix"
  type        = string
}

variable "environment" {
  description = "dev, staging or prod"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "root_volume_size_gb" {
  type    = number
  default = 20
}

variable "bucket_force_destroy" {
  description = "only true in dev"
  type        = bool
  default     = false
}

variable "bucket_versioning" {
  type    = bool
  default = true
}

variable "ec2_termination_protection" {
  description = "termination protection"
  type        = bool
  default     = false
}

variable "detailed_monitoring" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
