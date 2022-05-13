{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "${bucket_arn}",
        "${bucket_arn}/*"
      ],
      "Principal": {
        "AWS": "arn:aws:iam::568794283665:user/rahook_admin_cli"
      },
      "Condition": {
        "StringNotEquals": {
          "aws:PrincipalOrgID": "o-0rxo6itxil"
        }
      },
      "Effect": "Allow"
    }
  ]
}