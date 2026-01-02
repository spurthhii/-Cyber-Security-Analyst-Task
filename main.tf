provider "aws" {
  region = "us-east-1"  # Change to your preferred region
}

variable "alert_email" {
  description = "Email address to receive honeypot alerts"
  type        = string
}

# --- 1. SNS Topic for Alerts ---
resource "aws_sns_topic" "honeypot_alerts" {
  name = "honeypot-alert-topic"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.honeypot_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- 2. IAM Role for Lambda ---
resource "aws_iam_role" "lambda_role" {
  name = "honeypot_lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Policy: Allow logging to CloudWatch and Publishing to SNS
resource "aws_iam_role_policy" "lambda_policy" {
  name = "honeypot_lambda_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = "sns:Publish"
        Resource = aws_sns_topic.honeypot_alerts.arn
      }
    ]
  })
}

# --- 3. Lambda Function ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/honeypot.py"
  output_path = "${path.module}/honeypot_payload.zip"
}

resource "aws_lambda_function" "honeypot_func" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "honeypot-trigger"
  role          = aws_iam_role.lambda_role.arn
  handler       = "honeypot.lambda_handler"
  runtime       = "python3.9"
  timeout       = 10

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.honeypot_alerts.arn
    }
  }
}

# --- 4. API Gateway (REST API) ---
resource "aws_api_gateway_rest_api" "honeypot_api" {
  name        = "Internal-Admin-API"
  description = "Decoy API for internal administration"
}

# Catch-all Resource: {proxy+} matches any path
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.honeypot_api.id
  parent_id   = aws_api_gateway_rest_api.honeypot_api.root_resource_id
  path_part   = "{proxy+}"
}

# Catch-all Method: ANY matches GET, POST, PUT, DELETE, etc.
resource "aws_api_gateway_method" "proxy_any" {
  rest_api_id   = aws_api_gateway_rest_api.honeypot_api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

# Integration: Connect API Gateway to Lambda
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.honeypot_api.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy_any.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.honeypot_func.invoke_arn
}

# Handle root path ("/") separately (Optional but recommended)
resource "aws_api_gateway_method" "root_any" {
  rest_api_id   = aws_api_gateway_rest_api.honeypot_api.id
  resource_id   = aws_api_gateway_rest_api.honeypot_api.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "root_integration" {
  rest_api_id             = aws_api_gateway_rest_api.honeypot_api.id
  resource_id             = aws_api_gateway_rest_api.honeypot_api.root_resource_id
  http_method             = aws_api_gateway_method.root_any.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.honeypot_func.invoke_arn
}

# Deployment
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_integration.root_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.honeypot_api.id
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.honeypot_api.id
  stage_name    = "v1"
}

# Permission: Allow API Gateway to invoke Lambda
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.honeypot_func.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.honeypot_api.execution_arn}/*/*"
}