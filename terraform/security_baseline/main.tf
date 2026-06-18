data "aws_caller_identity" "current" {}

resource "aws_kms_key" "main" {
  description             = "CMK centrale - chiffrement plateforme"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms.json
}

data "aws_iam_policy_document" "kms" {
  statement {
    sid       = "Enable IAM User Permissions"
    effect    = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

    statement {
    sid     = "AllowCloudTrailEncrypt"
    effect  = "Allow"
    actions = ["kms:GenerateDataKey*", "kms:DescribeKey"]
    # GenerateDataKey* = CloudTrail chiffre chaque fichier de log
    # DescribeKey     = CloudTrail vérifie que la clé est valide avant d'écrire
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/plateforme-main"  # doit commencer par "alias/"
  target_key_id = aws_kms_key.main.key_id  # relie l'alias à la clé
}

resource "aws_s3_bucket" "main" {
  bucket = "slz-plateforme-main-${var.environment}"
  force_destroy = true #à passer à false en prod pour éviter la suppression accidentelle du bucket

}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid       = "AllowCloudTrailAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.main.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
    
    statement {
      sid       = "AllowCloudTrailWrite"
      effect    = "Allow"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.main.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }
      condition {
        test     = "StringEquals"
        variable = "s3:x-amz-acl"
        values   = ["bucket-owner-full-control"]
      }
    }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.main.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json
}

resource "aws_cloudtrail" "main" {
  name                          = "slz-cloudtrail-${var.environment}"
  s3_bucket_name                = aws_s3_bucket.main.bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation      = true
  kms_key_id                    = aws_kms_key.main.arn
}