# S3 Access Logging Solution - CloudFormation Deployment

A comprehensive AWS CloudFormation solution that provides detailed S3 bucket access logging with real-time processing and long-term archival. This solution captures all S3 operations (Create, Read, Update, Delete) with detailed information about who accessed what, when, and how.

## 🎯 Purpose

This CloudFormation template creates a complete logging infrastructure to monitor and audit S3 bucket access patterns. It's designed for organizations that need:

- **Security Auditing**: Track who is accessing your S3 data
- **Compliance Requirements**: Maintain detailed access logs for regulatory purposes
- **Operational Monitoring**: Understand usage patterns and detect anomalies
- **Incident Response**: Investigate security events with detailed forensic data

## 🏗️ Architecture Overview

The solution creates an integrated logging pipeline:

```
S3 Operations → CloudTrail → S3 Notification → Lambda → CloudWatch Logs + Weekly Archives
```

### Components Created

1. **CloudTrail Trail** - Captures S3 API calls using Advanced Event Selectors
2. **S3 CloudTrail Bucket** - Stores raw CloudTrail logs with automatic cleanup
3. **Lambda Function** - Processes CloudTrail logs and formats events
4. **CloudWatch Log Group** - Stores formatted, searchable logs
5. **S3 Archive Bucket** - Stores weekly aggregated logs with statistics
6. **IAM Roles & Policies** - Secure permissions for all components
7. **S3 Notifications** - Triggers Lambda when new CloudTrail logs arrive

## 📊 What Gets Logged

### S3 Operations Captured
- **CREATE/UPDATE**: PutObject, CopyObject, RestoreObject
- **READ**: GetObject, ListBucket, GetBucketLocation
- **DELETE**: DeleteObject, DeleteBucket

### Information Collected
- **Who**: User identity, type, source IP address
- **What**: Bucket name, object key, resources accessed
- **When**: Precise timestamp of each operation
- **How**: User agent, request ID, AWS region
- **Errors**: Error codes and messages for failed operations

## 📁 What Gets Created

### AWS Resources

| Resource Type | Purpose | Retention |
|---------------|---------|-----------|
| **CloudTrail Trail** | Captures S3 data events | Active logging |
| **S3 Bucket (CloudTrail)** | Raw CloudTrail logs | 30 days (configurable) |
| **S3 Bucket (Archives)** | Weekly log summaries | Indefinite |
| **CloudWatch Log Group** | Formatted, searchable logs | 7 days (configurable) |
| **Lambda Function** | Log processing and formatting | N/A |
| **IAM Roles** | Secure service permissions | N/A |

### Storage Locations

1. **Real-time Logs**: `/aws/s3/your-bucket-name/access-logs` (CloudWatch)
2. **Weekly Archives**: `s3://your-bucket-weekly-logs/weekly-logs/YYYY-WWW.json`
3. **Raw CloudTrail**: `s3://your-bucket-cloudtrail-logs/s3-access-logs/`

## 🚀 Deployment Instructions

### Prerequisites

- AWS account with CloudFormation permissions
- The S3 bucket you want to monitor must already exist
- Permissions to create IAM roles, CloudTrail, Lambda functions, and S3 buckets

### Step 1: Access CloudFormation Console

1. Sign in to the AWS Management Console
2. Navigate to **CloudFormation** service
3. Ensure you're in the correct AWS region where your S3 bucket is located

### Step 2: Create Stack

1. Click **Create stack** → **With new resources (standard)**
2. In the **Specify template** section:
   - Select **Upload a template file**
   - Click **Choose file** and select `s3-logging-template-v9.yaml`
   - Click **Next**

### Step 3: Configure Parameters

| Parameter | Description | Default | Notes |
|-----------|-------------|---------|-------|
| **S3BucketName** | Name of S3 bucket to monitor | `my-monitored-bucket` | **REQUIRED** - Must be exact bucket name |
| **LogRetentionDays** | CloudWatch log retention | `7` | Range: 1-365 days |
| **CloudTrailLogRetentionDays** | Raw CloudTrail log retention | `30` | Range: 1-3653 days |
| **ArchiveBucketName** | Custom archive bucket name | `""` | Leave empty for auto-generated name |

### Step 4: Configure Stack Options

1. **Stack name**: Enter descriptive name (e.g., `s3-access-logging-production`)
2. **Tags**: Add organizational tags (optional)
3. **Permissions**: Leave as default
4. **Advanced options**: Leave as default
5. Click **Next**

### Step 5: Review and Deploy

1. Review all configuration details
2. **⚠️ Important**: Check the box acknowledging CloudFormation will create IAM resources
3. Click **Submit**
4. Wait for **CREATE_COMPLETE** status (typically 3-5 minutes)

### Step 6: Verify Deployment

1. Check the **Outputs** tab for important resource information
2. Test with S3 operations:
   ```bash
   aws s3 cp test-file.txt s3://your-bucket-name/
   aws s3 ls s3://your-bucket-name/
   ```
3. Logs should appear in CloudWatch within 15-20 minutes

## 📋 Log Format

Each log entry contains structured JSON with complete audit information:

```json
{
  "timestamp": "2024-06-25T10:30:45Z",
  "operation": "READ",
  "event_name": "GetObject",
  "who": {
    "user_type": "IAMUser",
    "user_name": "john.doe",
    "source_ip": "203.0.113.12"
  },
  "what": {
    "resources": ["arn:aws:s3:::my-bucket/important-file.txt"],
    "bucket": "my-bucket",
    "key": "important-file.txt"
  },
  "how": {
    "user_agent": "aws-cli/2.0.0",
    "request_id": "ABC123DEF456",
    "aws_region": "us-east-1"
  },
  "response": {
    "error_code": "",
    "error_message": ""
  }
}
```

## 🔍 Querying Logs

### CloudWatch Logs Insights

Access via AWS Console → CloudWatch → Logs → Log groups → `/aws/s3/your-bucket-name/access-logs`

**Example Queries:**

```sql
# Show all operations from the last hour
fields @timestamp, operation, who.user_name, what.key
| filter @timestamp > @timestamp - 1h
| sort @timestamp desc

# Filter by specific user
fields @timestamp, operation, what.key, response.error_code
| filter who.user_name = "john.doe"
| sort @timestamp desc

# Show only DELETE operations
fields @timestamp, who.user_name, what.key, response.error_code
| filter operation = "DELETE"
| sort @timestamp desc

# Count operations by user
stats count() by who.user_name
| sort count desc
```

### AWS CLI Access

```bash
# View recent logs
aws logs filter-log-events \
  --log-group-name "/aws/s3/your-bucket-name/access-logs" \
  --start-time $(date -d "1 hour ago" +%s)000

# Filter for specific operations
aws logs filter-log-events \
  --log-group-name "/aws/s3/your-bucket-name/access-logs" \
  --filter-pattern "DELETE" \
  --start-time $(date -d "1 hour ago" +%s)000
```

### Weekly Archives

```bash
# List all weekly archive files
aws s3 ls s3://your-bucket-name-weekly-logs-123456789012/weekly-logs/

# Download specific week's archive
aws s3 cp s3://your-bucket-name-weekly-logs-123456789012/weekly-logs/2024-W25.json ./

# View archive with summary statistics
cat 2024-W25.json | jq '.summary'
```

## 💰 Cost Estimation

### Monthly Cost Breakdown (1,000 operations/day)

| Service | Component | Estimated Cost |
|---------|-----------|----------------|
| **CloudTrail** | Data events (30,000/month) | $3.00 |
| **Lambda** | Invocations + compute time | $0.50 |
| **CloudWatch Logs** | Ingestion (1GB) + Storage | $2.00 |
| **S3 (CloudTrail)** | Storage (5GB) + requests | $1.00 |
| **S3 (Archives)** | Storage (10GB) + requests | $1.50 |
| **Total** | | **~$8.00/month** |

### Cost by Usage Level

| Usage Level | Operations/Day | Monthly Cost |
|-------------|----------------|--------------|
| Light | 100 | $2-4 |
| Moderate | 1,000 | $6-10 |
| Heavy | 10,000 | $25-40 |
| Enterprise | 100,000 | $200-350 |

## 🛠️ Troubleshooting

### No Logs Appearing

1. **Verify S3 operations**: Ensure you're performing data events (PutObject, GetObject, DeleteObject)
2. **Check CloudTrail status**: Verify trail is active and logging
3. **Wait for processing**: Data events take 15-20 minutes to appear
4. **Check Lambda logs**: Look for processing errors in CloudWatch

### High Costs

1. **Review data event volume**: CloudTrail data events are the primary cost driver
2. **Adjust retention periods**: Reduce CloudWatch log retention
3. **Monitor usage**: Use AWS Cost Explorer to track spending

### Permission Errors

1. **IAM acknowledgment**: Ensure you checked the IAM resources box during deployment
2. **Regional deployment**: Deploy in same region as your S3 bucket
3. **Resource conflicts**: Check for naming conflicts with existing resources

## 🧹 Cleanup

To remove all resources and stop charges:

1. Go to CloudFormation console
2. Select your stack
3. Click **Delete**
4. Confirm deletion

**Note**: S3 buckets with content may need manual emptying before stack deletion completes.

## 🔧 Advanced Configuration

### Custom Event Filtering

The solution can be extended to:
- Filter specific S3 operations using `eventName` field selectors
- Add custom alerting with SNS integration
- Extend retention policies for compliance requirements
- Add encryption for sensitive log data

### Integration Options

- **SIEM Integration**: Export logs to security information systems
- **Data Analytics**: Process weekly archives with AWS Analytics services
- **Alerting**: Add CloudWatch alarms for suspicious activity patterns
- **Compliance Reporting**: Automated compliance report generation

## 📈 Monitoring and Health Checks

Monitor these key metrics for solution health:

- **CloudTrail delivery status**: Ensure logs are being delivered
- **Lambda function errors**: Monitor processing failures
- **CloudWatch log ingestion**: Verify formatted logs are appearing
- **S3 storage usage**: Track archive bucket growth
- **Cost trends**: Monitor monthly spending patterns

## 🔒 Security Considerations

- **Access Control**: Implement proper IAM policies for log access
- **Encryption**: Consider enabling S3 bucket encryption
- **Network Security**: Logs include source IP addresses for analysis
- **Data Retention**: Configure appropriate retention for compliance needs
- **Audit Trail**: The solution itself creates an audit trail of its operations

---

## License

**PRODUCTION DEPLOYMENT NOTICE**

This solution is intended as a reference architecture and is provided for educational and testing purposes only.

**Required before production deployment:**
- Error handling implementation
- Logging implementation  
- Compliance validation
- High availability configuration
- Performance optimization

No warranty is provided, express or implied. Production use requires thorough evaluation and testing for your specific environment.
