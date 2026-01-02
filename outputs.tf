output "honeypot_url" {
  value       = "${aws_api_gateway_stage.prod.invoke_url}/"
  description = "The root URL of the honeypot API"
}