# Cleanup (to stop AWS charges)

Delete in this order, in **both** regions unless noted:

1. Auto Scaling Groups (`dr-asg-east`, `dr-asg-west`)
2. Load balancers (`dr-alb-east`, `dr-alb-west`)
3. Target groups (`dr-tg-east`, `dr-tg-west`)
4. Launch templates and security groups
5. Route 53 health check (`dr-east-health`) - us-east-1
6. CloudWatch alarm (`dr-east-down`) and SNS topic (`dr-alerts`)
7. DynamoDB: delete the Oregon replica, then the table `DRDemoTable`
8. S3: empty, then delete both buckets (delete the replication rule first)
