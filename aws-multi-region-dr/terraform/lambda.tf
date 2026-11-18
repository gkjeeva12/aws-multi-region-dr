# Optional automated recovery: when the alarm fires, scale up the recovery Auto Scaling Group.
# Enable with: enable_lambda = true

data "archive_file" "recovery" {
  count       = var.enable_lambda ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/recovery_lambda.zip"

  source {
    filename = "index.py"
    content  = <<-PY
      import os
      import boto3

      def handler(event, context):
          client = boto3.client("autoscaling", region_name=os.environ["RECOVERY_REGION"])
          name = os.environ["ASG_NAME"]
          desired = int(os.environ["DESIRED"])
          client.update_auto_scaling_group(
              AutoScalingGroupName=name,
              MinSize=desired,
              DesiredCapacity=desired,
          )
          return {"scaled": name, "desired": desired}
    PY
  }
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  count              = var.enable_lambda ? 1 : 0
  name               = "${var.project}-recovery-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  count      = var.enable_lambda ? 1 : 0
  role       = aws_iam_role.lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_scale" {
  count = var.enable_lambda ? 1 : 0
  name  = "scale-recovery-asg"
  role  = aws_iam_role.lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:DescribeAutoScalingGroups",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_lambda_function" "recovery" {
  count    = var.enable_lambda ? 1 : 0
  provider = aws.monitoring

  function_name    = "${var.project}-scale-up-recovery"
  role             = aws_iam_role.lambda[0].arn
  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.recovery[0].output_path
  source_code_hash = data.archive_file.recovery[0].output_base64sha256
  timeout          = 30

  environment {
    variables = {
      RECOVERY_REGION = var.recovery_region
      ASG_NAME        = module.recovery_web.asg_name
      DESIRED         = tostring(var.recovery_failover_capacity)
    }
  }
}

resource "aws_lambda_permission" "from_sns" {
  count    = var.enable_lambda ? 1 : 0
  provider = aws.monitoring

  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.recovery[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

resource "aws_sns_topic_subscription" "lambda" {
  count     = var.enable_lambda ? 1 : 0
  provider  = aws.monitoring
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.recovery[0].arn
}
