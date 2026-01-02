# AWS Serverless Honeypot Setup

A serverless honeypot deployment on AWS to detect and log malicious activity attempts.

## Prerequisites

Before you begin, ensure you have the following installed and configured:

- **AWS CLI** - Installed and configured with your credentials
  ```bash
  aws configure
  ```
- **Terraform** - Version 1.0 or higher
- **Python** - Version 3.9 or higher

## Deployment Steps

### 1. Initialize Terraform

Open your terminal in the project directory and initialize Terraform:

```bash
terraform init
```

### 2. Deploy Infrastructure

Run the plan and apply commands. You will be prompted to provide an email address for receiving alerts:

```bash
terraform apply -var="alert_email=your-email@example.com"
```

Type `yes` when prompted to confirm the deployment.

### 3. Confirm SNS Subscription

After deployment:

1. Check the email inbox you provided during deployment
2. Look for an email with the subject **"AWS Notification - Subscription Confirmation"**
3. Click the confirmation link in the email

> **Important:** If you don't confirm the subscription, you won't receive alerts.

### 4. Note the Honeypot URL

After successful deployment, Terraform will output a `honeypot_url`. It will look something like:

```
https://xyz123.execute-api.us-east-1.amazonaws.com/v1/
```

Save this URL for testing.

## Testing the Honeypot

Simulate attacker behavior using the following curl commands:

### Simulate Root Access Attempt

```bash
curl -X GET https://<your-api-id>.execute-api.us-east-1.amazonaws.com/v1/
```

### Simulate Admin Login Attempt

```bash
curl -X POST https://<your-api-id>.execute-api.us-east-1.amazonaws.com/v1/admin/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin", "password":"password123"}'
```

Replace `<your-api-id>` with your actual API Gateway ID from the honeypot URL.

## Verification

### Check Email Alerts

You should receive an email with the subject **"Honeypot Triggered"** containing details about the simulated attack.

### Check CloudWatch Logs

1. Navigate to **AWS Console** → **CloudWatch** → **Log Groups**
2. Find the log group named `/aws/lambda/honeypot-trigger`
3. View the latest log stream to see structured JSON logs containing:
   - Source IP address
   - Request headers
   - Request body
   - Timestamp

## Cleanup

To remove all deployed resources and avoid ongoing AWS charges:

```bash
terraform destroy -var="alert_email=your-email@example.com"
```

Type `yes` when prompted to confirm the destruction of resources.

## Architecture

This honeypot uses the following AWS services:

- **API Gateway** - Exposes the honeypot endpoints
- **Lambda** - Processes and logs incoming requests
- **CloudWatch Logs** - Stores detailed request logs
- **SNS** - Sends email alerts when the honeypot is triggered
- **IAM** - Manages permissions between services

## Security Notes

- The honeypot intentionally accepts all requests to appear vulnerable
- All interactions are logged for security analysis
- No sensitive data should be stored in the honeypot responses
- Regularly review CloudWatch logs for patterns of malicious activity