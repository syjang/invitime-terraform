variable "name_prefix" { type = string }
variable "domain_names" { type = list(string) }
variable "certificate_arn" { type = string }

resource "aws_s3_bucket" "site" {
  bucket        = "${var.name_prefix}-site"
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule { object_ownership = "BucketOwnerPreferred" }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for ${var.name_prefix}"
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid = "AllowCloudFrontRead",
      Effect = "Allow",
      Principal = { CanonicalUser = aws_cloudfront_origin_access_identity.oai.s3_canonical_user_id },
      Action = ["s3:GetObject"],
      Resource = ["${aws_s3_bucket.site.arn}/*"]
    }]
  })
}

resource "aws_cloudfront_distribution" "this" {
  provider = aws.us_east_1
  enabled             = true
  is_ipv6_enabled     = true
  aliases             = var.domain_names
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id   = "s3-${aws_s3_bucket.site.id}"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "s3-${aws_s3_bucket.site.id}"
    viewer_protocol_policy = "redirect-to-https"
    compress = true
    forwarded_values {
      query_string = true
      cookies { forward = "none" }
    }
  }

  custom_error_response {
    error_code = 404
    response_code = 200
    response_page_path = "/index.html"
  }
  custom_error_response {
    error_code = 403
    response_code = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = var.certificate_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
  }
}

output "bucket_name" { value = aws_s3_bucket.site.id }
output "distribution_id" { value = aws_cloudfront_distribution.this.id }
output "distribution_domain_name" { value = aws_cloudfront_distribution.this.domain_name }
output "distribution_zone_id" { value = aws_cloudfront_distribution.this.hosted_zone_id }

