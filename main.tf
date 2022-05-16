provider "aws" {
  region  = "${var.aws_region}"
  access_key = "<access_key>"
  secret_key = "<secret_key>"
}

# --------------------------------------------------------------------------------------------------------------
# various data lookups
# --------------------------------------------------------------------------------------------------------------
data "aws_ami" "target_ami" {
  most_recent = true
  owners = ["amazon"]
  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["${var.nifi_ami_name}"]
  }
}

data "aws_subnet" "bastion_subnet" {
  cidr_block = "${var.bastion_subnet_cidr}"
}

data "aws_vpc" "bastion_vpc" {
  cidr_block = "${var.bastion_vpc_cidr}"
}

data "template_file" "assume_policy" {
  template = "${file("${path.module}/policies/iam_assume_policy.json.tpl")}"
}

# TODO: parameterise that nacl
variable "default_network_acl_id" {
  default = "acl-6c6a2f05"
}

# ----------------------------------------------------------------------------------------
# instance for NIFI.
# ----------------------------------------------------------------------------------------

resource "aws_instance" "nifi" {
  ami                    = "${data.aws_ami.target_ami.id}"
  instance_type          = "${var.nifi_instance_type}"
  key_name               = "${var.nifi_key}"
  subnet_id              = "${data.aws_subnet.bastion_subnet.id}"
  vpc_security_group_ids = ["${aws_security_group.nifi_access.id}", "${aws_security_group.nifi_ssh.id}"]

  iam_instance_profile = "${aws_iam_instance_profile.nifi_profile.name}"

  root_block_device {
    volume_type = "gp2"
    volume_size = "${var.root_vol_size}"
  }

  tags = {
    Name    = "NiFi"
    Project = "${var.tags["project"]}"
    Owner   = "${var.tags["owner"]}"
    Client  = "${var.tags["client"]}"
  }

  volume_tags = {
    Project = "${var.tags["project"]}"
    Owner   = "${var.tags["owner"]}"
    Client  = "${var.tags["client"]}"
  }

  user_data = <<EOF
#!/bin/bash
yum update -y
yum install -y java-1.8.0-openjdk
yum remove -y java-1.7.0-openjdk
adduser nifi
sudo -u nifi sh -c 'cd ~nifi; wget -q http://mirrors.rackhosting.com/apache/nifi/1.4.0/nifi-1.4.0-bin.tar.gz'
sudo -u nifi sh -c 'cd ~nifi; tar xfz nifi*tar.gz'
sudo -u nifi sh -c 'cd ~nifi; ln -s nifi-1.4.0 nifi'
~nifi/nifi/bin/nifi.sh install
printf "\n\nexport JAVA_HOME=/usr/lib/jvm/jre-1.8.0-openjdk\n" >> ~nifi/nifi/bin/nifi-env.sh
sed -i 's/run.as=.*/run.as=nifi/' ~nifi/nifi/conf/bootstrap.conf
service nifi start
EOF
}

resource "aws_security_group" "nifi_access" {
  name        = "nifi_access"
  description = "allows access to nifi"
  vpc_id      = "${data.aws_vpc.bastion_vpc.id}"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = "${var.nifi_inbound}"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "nifi_ssh" {
  name        = "nifi_ssh"
  description = "allows ssh to nifi"
  vpc_id      = "${data.aws_vpc.bastion_vpc.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = "${var.nifi_inbound}"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# create the IAM role
resource "aws_iam_role" "nifi_role" {
  name_prefix           = "nifi"
  path                  = "/"
  force_detach_policies = true
  assume_role_policy    = "${data.template_file.assume_policy.rendered}"
}

# Read the template file and inject ARNs
data "template_file" "instance_profile" {
  template = "${file("policies/instance-profile.json.tpl")}"

  vars = {
    bucket_arn = "${aws_s3_bucket.s3_landing.arn}"
    queue_arn  = "${aws_sqs_queue.s3_landing_queue.arn}"
    output_bucket_arn = "${aws_s3_bucket.s3_output.arn}"
  }
}

# attach the policy JSON to the role
resource "aws_iam_role_policy" "nifi" {
  name_prefix = "nifi"
  role        = "${aws_iam_role.nifi_role.id}"
  policy      = "${data.template_file.instance_profile.rendered}"
}

# attach the role to the instance
resource "aws_iam_instance_profile" "nifi_profile" {
  name_prefix = "nifi"
  role        = "${aws_iam_role.nifi_role.name}"
}

# ----------------------------------------------------------------------------------------
# some S3 buckets.
# ----------------------------------------------------------------------------------------
resource "aws_s3_bucket" "s3_landing" {
  bucket_prefix = "${var.landing_bucket}"
  acl           = "private"
  #region        = "${var.aws_region}"

  tags = {
    Name    = "s3_landing"
    Project = "${var.tags["project"]}"
    Owner   = "${var.tags["owner"]}"
    Client  = "${var.tags["client"]}"
  }
}

resource "aws_s3_bucket" "s3_output" {
  bucket_prefix = "${var.output_bucket}"
  acl           = "private"
  #region        = "${var.aws_region}"

  tags = {
    Name    = "s3_output"
    Project = "${var.tags["project"]}"
    Owner   = "${var.tags["owner"]}"
    Client  = "${var.tags["client"]}"
  }
}

# ----------------------------------------------------------------------------------------
# dropzone bucket policies
# ----------------------------------------------------------------------------------------

data "template_file" "dropzone_write" {
  template = "${file("policies/s3-dropzone-policy.json.tpl")}"

  vars = {
    bucket_arn = "${aws_s3_bucket.s3_landing.arn}"
  }
}

resource "aws_s3_bucket_policy" "dropzone_write" {
  bucket = "${aws_s3_bucket.s3_landing.id}"
  policy = "${data.template_file.dropzone_write.rendered}"
}

# ----------------------------------------------------------------------------------------
# output bucket policies
# ----------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------
# SQS queue
# ----------------------------------------------------------------------------------------

resource "aws_sqs_queue" "s3_landing_queue" {
  name_prefix = "nifi_demo"

  visibility_timeout_seconds = 60

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:SendMessage",
      "Resource": "arn:aws:sqs:*:*:s3-event-notification-queue",
      "Condition": {
        "ArnEquals": { "aws:SourceArn": "${aws_s3_bucket.s3_landing.arn}" }
      }
    }
  ]
}
POLICY

  tags = {
    Name    = "s3_landing_queue"
    Project = "${var.tags["project"]}"
    Owner   = "${var.tags["owner"]}"
    Client  = "${var.tags["client"]}"
  }
}

data "template_file" "sqs_policy" {
  template = "${file("policies/sqs-policy.json.tpl")}"

  vars = {
    bucket_arn = "${aws_s3_bucket.s3_landing.arn}"
    queue_arn  = "${aws_sqs_queue.s3_landing_queue.arn}"
  }
}

resource "aws_sqs_queue_policy" "s3_landing_policy" {
  queue_url = "${aws_sqs_queue.s3_landing_queue.id}"
  policy    = "${data.template_file.sqs_policy.rendered}"
}

resource "aws_s3_bucket_analytics_configuration" "example-entire-bucket" {
  bucket = aws_s3_bucket.s3_landing.bucket
  name   = "EntireBucket"

  storage_class_analysis {
    data_export {
      destination {
        s3_bucket_destination {
          bucket_arn = aws_s3_bucket.s3_output.arn
        }
      }
    }
  }
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = "${aws_s3_bucket.s3_landing.id}"

  queue {
    queue_arn = "${aws_sqs_queue.s3_landing_queue.arn}"
    events    = ["s3:ObjectCreated:*"]
  }
}

#--- send email notification
module "ses_notification_service" {
  source = "dwp/ses-notification-service/aws"
  bucket_access_logging = [
    {
      target_bucket = "${aws_s3_bucket.s3_output.id}"
      target_prefix = "s3Logs/ses_notification_service/"
    },
  ]
  region = "${var.aws_region}"
  domain = "example.com"
  lambda_sns_to_ses_mailer_zip = {
    base_path = ".",
    file_name   = "aws-sns-to-ses-mailer-0.0.1.zip"
  }
}

resource "aws_s3_bucket_object" "mailing_list" {
  bucket = "${aws_s3_bucket.s3_output.id}"
  key    = "mailing_list.csv.gz"
  source = "mailing_list.csv.gz"
  etag   = "${md5(file("mailing_list.csv.gz"))}"
}


resource "aws_s3_bucket_object" "email_template" {
  bucket = "${aws_s3_bucket.s3_output.id}"
  key    = "mail_template.html"
  source = "mail_template.html"
  etag   = "${md5(file("mail_template.html"))}"
}

resource "aws_sns_topic" "danz_zuper_zervice" {
  name = "danz_zuper_zervice"
  display_name = "Danz Zuper Zervice - ${terraform.workspace}"
}

resource "aws_sns_topic_subscription" "sns_to_ses_mailer_lambda" {
  topic_arn = "${aws_sns_topic.danz_zuper_zervice.arn}"
  protocol  = "lambda"
  endpoint  = "${module.ses_notification_service.sns_to_ses_mailer_lambda_arn}"
}

resource "aws_lambda_permission" "ses_mailer" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = "${module.ses_notification_service.sns_to_ses_mailer_lambda_arn}"
  principal     = "sns.amazonaws.com"
  source_arn    = "${aws_sns_topic.danz_zuper_zervice.arn}"
}
