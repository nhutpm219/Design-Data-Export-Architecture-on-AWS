output "s3_landing" {
  value = "${aws_s3_bucket.s3_landing.arn}"
}

output "s3_output" {
  value = "${aws_s3_bucket.s3_output.arn}"
}

output "sqs_queue" {
  value = "${aws_sqs_queue.s3_landing_queue.arn}"
}

output "nifi_public_dns" {
  value = "${aws_instance.nifi.public_dns}"
}