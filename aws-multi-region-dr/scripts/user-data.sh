#!/bin/bash
# EC2 User Data for Amazon Linux 2023
# Installs Apache and serves a page showing which region/AZ/instance responded.
dnf update -y
dnf install -y httpd
systemctl enable --now httpd

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
HOST=$(hostname -f)

# Health check endpoint used by the ALB target group and Route 53
echo "OK" > /var/www/html/health

cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html>
<head><title>DR Demo</title></head>
<body style="font-family:sans-serif;text-align:center;margin-top:80px;">
  <h1>AWS Multi-Region DR Demo</h1>
  <h2>Served from: $REGION</h2>
  <p>Availability Zone: $AZ</p>
  <p>Instance: $HOST</p>
</body>
</html>
HTML
