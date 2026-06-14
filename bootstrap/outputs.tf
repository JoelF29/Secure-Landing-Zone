output "bucket_name" {
  value       = aws_s3_bucket.state.bucket
  description = "Name of the S3 bucket"
}