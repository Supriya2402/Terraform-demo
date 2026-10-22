
# SQS queue: stores employee check requests
resource "aws_sqs_queue" "employee_requests" {
  name                       = "employee-check-requests"
  visibility_timeout_seconds = 60
}

# SNS topic: publishes employee notifications
resource "aws_sns_topic" "employee_notifications" {
  name = "employee-check-notifications"
}

# CloudWatch log groups for the two Lambda functions
resource "aws_cloudwatch_log_group" "lambda1_logs" {
  name              = "/aws/lambda/employee-api-handler"
  retention_in_days = 3
}

resource "aws_cloudwatch_log_group" "lambda2_logs" {
  name              = "/aws/lambda/employee-processor"
  retention_in_days = 3
}

# IAM role shared by both Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "employee-check-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Permissions for logs, SQS, and SNS
resource "aws_iam_role_policy" "lambda_policy" {
  name = "employee-check-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.employee_requests.arn
      },
      {
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = aws_sns_topic.employee_notifications.arn
      }
    ]
  })
}

# Lambda 1: API handler
resource "aws_lambda_function" "api_handler" {
  function_name = "employee-api-handler"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.12"
  handler       = "lambda_api.lambda_handler"
  filename      = "${path.module}/lambda_api.zip"
  timeout       = 10

  source_code_hash = filebase64sha256("${path.module}/lambda_api.zip")

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.employee_requests.url
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda1_logs
  ]
}

# Lambda 2: processes SQS messages and publishes to SNS
resource "aws_lambda_function" "employee_processor" {
  function_name = "employee-processor"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.12"
  handler       = "lambda_processor.lambda_handler"
  filename      = "${path.module}/lambda_processor.zip"
  timeout       = 15

  source_code_hash = filebase64sha256("${path.module}/lambda_processor.zip")

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.employee_notifications.arn
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda2_logs
  ]
}

# Automatically invoke Lambda 2 when a message enters SQS
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.employee_requests.arn
  function_name    = aws_lambda_function.employee_processor.arn
  batch_size       = 1
}

# API Gateway HTTP API
resource "aws_apigatewayv2_api" "employee_api" {
  name          = "employee-check-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "api_integration" {
  api_id                 = aws_apigatewayv2_api.employee_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api_handler.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "check_employee" {
  api_id    = aws_apigatewayv2_api.employee_api.id
  route_key = "POST /check-employee"
  target    = "integrations/${aws_apigatewayv2_integration.api_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.employee_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.employee_api.execution_arn}/*/*"
}

# EventBridge rule: optional employee-check event trigger
resource "aws_cloudwatch_event_rule" "employee_check" {
  name = "employee-check-event-rule"

  event_pattern = jsonencode({
    source      = ["demo.employee"]
    detail-type = ["EmployeeDetailsChecked"]
  })
}

resource "aws_cloudwatch_event_target" "event_to_lambda" {
  rule      = aws_cloudwatch_event_rule.employee_check.name
  target_id = "employee-api-handler"
  arn       = aws_lambda_function.api_handler.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.employee_check.arn
}

output "api_url" {
  value = "${aws_apigatewayv2_api.employee_api.api_endpoint}/check-employee"
}

output "sqs_queue_url" {
  value = aws_sqs_queue.employee_requests.url
}

output "sns_topic_arn" {
  value = aws_sns_topic.employee_notifications.arn
}
