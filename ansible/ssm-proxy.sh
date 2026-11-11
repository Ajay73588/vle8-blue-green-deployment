#!/usr/bin/env bash
exec "/mnt/c/Program Files/Amazon/AWSCLIV2/aws.exe" ssm start-session \
  --target "$1" \
  --document-name AWS-StartSSHSession \
  --parameters "portNumber=$2" \
  --region "${AWS_REGION:-ap-south-1}"
