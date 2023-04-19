# Copyright (c) 2023, Xgrid Inc, https://xgrid.co

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#        http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

data "archive_file" "most_expensive_service_archive" {
  type        = "zip"
  source_file = "../lambda_functions/expensive_services_detail/most_expensive_service.py"
  output_path = "${path.module}/most_expensive_service.zip"
}

# Creating IAM Role for Lambda functions
resource "aws_iam_role" "most_expensive_service_role" {
  name = "${var.namespace}-most_expensive_service_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "TotalAccountCost"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
  tags                = merge(local.tags, tomap({ "Name" = "${var.namespace}-most_expensive_service_role" }))

}

# Creating Inline policy
resource "aws_iam_role_policy" "most_expensive_service_policy" {
  name = "${var.namespace}-most_expensive_service_policy"
  role = aws_iam_role.most_expensive_service_role.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "TotalAccountCost",
        "Effect" : "Allow",
        "Action" : [
          "ce:GetCostAndUsage",
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DetachNetworkInterface",
          "ec2:AttachNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeRegions"
        ]
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_lambda_function" "most_expensive_service" {
  #ts:skip=AWS.LambdaFunction.LM.MEIDUM.0063 We are aware of the risk and choose to skip this rule
  #ts:skip=AWS.LambdaFunction.Logging.0470 We are aware of the risk and choose to skip this rule
  #ts:skip=AWS.LambdaFunction.EncryptionandKeyManagement.0471 We are aware of the risk and choose to skip this rule
  function_name = "${var.namespace}-most_expensive_service_lambda"
  role          = aws_iam_role.most_expensive_service_role.arn
  runtime       = "python3.9"
  handler       = "most_expensive_service.lambda_handler"
  filename      = data.archive_file.most_expensive_service_archive.output_path
  environment {
    variables = {
      prometheus_ip = "${var.prometheus_ip}:9091"
    }
  }
  memory_size = var.memory_size
  timeout     = var.timeout
  layers      = [var.prometheus_layer]
  vpc_config {
    subnet_ids         = [var.subnet_id]
    security_group_ids = [var.security_group_id]
  }
  tags = merge(local.tags, tomap({ "Name" = "${var.namespace}-most_expensive_service" }))

}

resource "null_resource" "delete_lambda_zip_file" {
  triggers = {
    lambda_function_arn = aws_lambda_function.most_expensive_service.arn
  }
  provisioner "local-exec" {
    command = "rm -r ${data.archive_file.most_expensive_service_archive.output_path}"
  }
}

resource "aws_iam_policy" "most_expensive_service" {
  name = "${var.namespace}-most_expensive_service_eventbridge_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "lambda:InvokeFunction"
        ]
        Effect   = "Allow"
        Resource = aws_lambda_function.most_expensive_service.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "most_expensive_service" {
  policy_arn = aws_iam_policy.most_expensive_service.arn
  role       = aws_iam_role.most_expensive_service_role.name
}

# Define the EventBridge rule
resource "aws_cloudwatch_event_rule" "most_expensive_service" {
  name                = "${var.namespace}-most_expensive_service-rule"
  description         = "Trigger the Lambda function every week on Monday"
  schedule_expression = var.cron_jobs_schedule["most_expensive_service_cron"]
  tags                = merge(local.tags, tomap({ "Name" = "${var.namespace}-most_expensive_service_rule" }))
}

# Define the EventBridge target to invoke the Lambda function
resource "aws_cloudwatch_event_target" "most_expensive_service" {
  rule = aws_cloudwatch_event_rule.most_expensive_service.name
  arn  = aws_lambda_function.most_expensive_service.arn
}

resource "aws_lambda_permission" "most_expensive_service" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.most_expensive_service.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.most_expensive_service.arn
}
