output "bucket_name" {
  value = aws_s3_bucket.data.id
}

output "bucket_arn" {
  value = aws_s3_bucket.data.arn
}

output "instance_id" {
  value = aws_instance.app.id
}

output "instance_role_arn" {
  value = aws_iam_role.ec2.arn
}
