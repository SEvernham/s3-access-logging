# S3 Access Logging Solution - CloudFormation Console Deployment

This CloudFormation template creates a comprehensive logging solution for S3 bucket access that captures all CRUD operations with detailed information about who, what, when, and how. The solution includes weekly log archives stored in a separate S3 bucket.

## Architecture Overview

The solution consists of:

1. **CloudTrail** - Captures all S3 API calls for your specified bucket
2. **Lambda Function** - Processes CloudTrail logs and formats them into readable entries
3. **CloudWatch Logs** - Stores formatted, human-readable logs with configurable retention
4. **S3 Bucket (CloudTrail)** - Stores raw CloudTrail logs with automatic cleanup
5. **S3 Bucket (Weekly Archives)** - Stores weekly aggregated logs with summary statistics

## Features

- **Complete CRUD Monitoring**: Captures Create, Read, Update, Delete operations
- **Detailed Information**: 
  - **Who**: User identity, type, source IP address
  - **What**: Bucket name, object key, resources accessed
  - **When**: Precise timestamp of each operation
  - **How**: User agent, request ID, AWS region
- **Error Tracking**: Captures error codes and messages for failed operations
- **Dual Storage**: Real-time logs in CloudWatch + weekly archives in S3
- **Weekly Aggregation**: Logs grouped by week with comprehensive summary statistics
- **Long-term Retention**: Weekly archives kept for 1 year (configurable)
- **Multiple Query Options**: CloudWatch Logs Insights, AWS CLI, and direct S3 access

## Deployment via AWS CloudFormation Console

### Prerequisites

- AWS account with appropriate permissions for:
  - CloudFormation stack creation
  - CloudTrail management
  - Lambda function deployment
  - CloudWatch Logs access
  - S3 bucket creation and management
  - IAM role creation
- The S3 bucket you want to monitor must already exist

### Step 1: Access CloudFormation Console

1. Sign in to the AWS Management Console
2. Navigate to **CloudFormation** service
3. Ensure you're in the correct AWS region where your S3 bucket is located

### Step 2: Create Stack

1. Click **Create stack** → **With new resources (standard)**
2. In the **Specify template** section:
   - Select **Upload a template file**
   - Click **Choose file** and select `s3-logging-template.yaml`
   - Click **Next**

### Step 3: Configure Stack Parameters

On the **Specify stack details** page:

1. **Stack name**: Enter a descriptive name (e.g., `s3-access-logging-stack`)

2. **Parameters**:
   - **S3BucketName**: Enter the exact name of your S3 bucket to monitor (REQUIRED)
   - **LogRetentionDays**: Number of days to retain logs in CloudWatch (default: 7, range: 1-365)
   - **ArchiveBucketName**: Leave empty to auto-generate, or specify a custom name for the weekly archive bucket

3. Click **Next**

### Step 4: Configure Stack Options

1. **Tags** (optional): Add tags for resource organization
2. **Permissions**: Leave as default (CloudFormation will create necessary IAM roles)
3. **Stack failure options**: Choose your preferred rollback behavior
4. **Advanced options**: Leave as default unless you have specific requirements
5. Click **Next**

### Step 5: Review and Deploy

1. Review all configuration details
2. **Important**: Check the box acknowledging that CloudFormation will create IAM resources
3. Click **Submit**

### Step 6: Monitor Deployment

1. The stack creation will take 3-5 minutes
2. Monitor the **Events** tab for progress
3. Wait for status to show **CREATE_COMPLETE**

### Step 7: Verify Deployment

After successful deployment:

1. Go to the **Outputs** tab to see important resource information
2. Note the **LogGroupName** for querying logs
3. Test the setup by performing operations on your monitored S3 bucket:
   ```bash
   aws s3 ls s3://your-bucket-name/
   aws s3 cp test-file.txt s3://your-bucket-name/
   ```
4. Logs should appear in CloudWatch within 5-15 minutes

## Log Format

Each log entry contains structured information:

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

## Querying Logs

### Using CloudWatch Console

1. Navigate to **CloudWatch** → **Logs** → **Log groups**
2. Find `/aws/s3/your-bucket-name/access-logs`
3. Click on the log group to view log streams
4. Use **CloudWatch Logs Insights** for advanced queries:

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

# Show only errors
fields @timestamp, operation, who.user_name, what.key, response.error_code
| filter response.error_code != ""
| sort @timestamp desc

# Count operations by user
stats count() by who.user_name
| sort count desc
```

### Using AWS CLI

After deployment, use the commands from the CloudFormation **Outputs** tab:

```bash
# View recent logs (replace with your actual log group name)
aws logs filter-log-events \
  --log-group-name "/aws/s3/your-bucket-name/access-logs" \
  --start-time $(date -d "1 hour ago" +%s)000

# Filter for specific user
aws logs filter-log-events \
  --log-group-name "/aws/s3/your-bucket-name/access-logs" \
  --filter-pattern "john.doe" \
  --start-time $(date -d "1 hour ago" +%s)000

# Filter for delete operations
aws logs filter-log-events \
  --log-group-name "/aws/s3/your-bucket-name/access-logs" \
  --filter-pattern "DELETE" \
  --start-time $(date -d "1 hour ago" +%s)000

# Use CloudWatch Logs Insights via CLI
aws logs start-query \
  --log-group-name "/aws/s3/your-bucket-name/access-logs" \
  --start-time $(date -d "1 hour ago" +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, operation, who.user_name | sort @timestamp desc'
```

### Accessing Weekly Archives

Weekly archives are stored in the S3 bucket created by the template:

```bash
# List all weekly archive files
aws s3 ls s3://your-bucket-name-weekly-logs-123456789012/weekly-logs/

# Download a specific week's archive
aws s3 cp s3://your-bucket-name-weekly-logs-123456789012/weekly-logs/2024-W25.json ./

# View archive metadata
aws s3api head-object \
  --bucket your-bucket-name-weekly-logs-123456789012 \
  --key weekly-logs/2024-W25.json
```

### Weekly Archive File Structure

Each weekly archive contains:

```json
{
  "week": "2024-W25",
  "generated_at": "2024-06-24T10:30:00",
  "total_events": 1250,
  "summary": {
    "total_events": 1250,
    "error_count": 15,
    "top_operations": {
      "READ": 800,
      "CREATE/UPDATE": 350,
      "DELETE": 100
    },
    "top_users": {
      "john.doe": 500,
      "jane.smith": 300,
      "service-account": 450
    },
    "top_source_ips": {
      "203.0.113.12": 600,
      "198.51.100.5": 400,
      "192.0.2.10": 250
    },
    "unique_users": 15,
    "unique_ips": 8
  },
  "logs": [
    // Array of all log entries for the week
  ]
}
```

## Operation Mapping

The solution maps S3 API events to CRUD operations:

- **CREATE/UPDATE**: PutObject, CopyObject, RestoreObject, PutBucketVersioning
- **READ**: GetObject, ListBucket, GetBucketLocation, GetBucketVersioning
- **DELETE**: DeleteObject, DeleteBucket

## Cost Estimation

### Monthly Cost Breakdown (Moderate Usage: ~1,000 operations/day)

| Service | Component | Estimated Cost |
|---------|-----------|----------------|
| **CloudTrail** | Data events (30,000/month) | $3.00 |
| **Lambda** | Invocations + compute time | $0.50 |
| **CloudWatch Logs** | Ingestion (1GB) + Storage | $2.00 |
| **S3 (CloudTrail)** | Storage (5GB) + requests | $1.00 |
| **S3 (Archives)** | Storage (10GB) + requests | $1.50 |
| **Total** | | **~$8.00/month** |

### Cost Scaling by Usage Level

| Usage Level | Operations/Day | Estimated Monthly Cost |
|-------------|----------------|------------------------|
| Light | 100 | $2-4 |
| Moderate | 1,000 | $6-10 |
| Heavy | 10,000 | $25-40 |
| Enterprise | 100,000 | $200-350 |

### Cost Optimization Tips

1. **Adjust Log Retention**: Reduce CloudWatch log retention to 1-3 days if you primarily use weekly archives
2. **Filter Events**: Modify the CloudTrail event selector to capture only specific operations
3. **Archive Strategy**: Consider moving older weekly archives to S3 Glacier for long-term storage
4. **Regional Deployment**: Deploy in the same region as your S3 bucket to avoid cross-region charges

## Troubleshooting

### No Logs Appearing

1. **Verify S3 Bucket Exists**: Ensure the monitored bucket name is correct and exists
2. **Check CloudTrail Status**:
   - Go to CloudTrail console
   - Verify the trail is active and logging
3. **Check Lambda Function**:
   - Go to Lambda console
   - Check the function logs in CloudWatch for errors
4. **Verify Permissions**: Ensure all IAM roles were created successfully

### Logs Delayed

- CloudTrail typically delivers logs within 5-15 minutes
- Lambda processing adds 1-2 minutes additional delay
- Check Lambda function duration and errors

### High Costs

1. **Review CloudTrail Data Events**: These are the primary cost driver
2. **Adjust Log Retention**: Reduce retention period in CloudWatch
3. **Monitor Usage**: Use AWS Cost Explorer to track spending
4. **Consider Filtering**: Modify event selectors to capture fewer operations

### Permission Errors

1. **CloudFormation IAM Acknowledgment**: Ensure you checked the IAM resources box during deployment
2. **Cross-Region Issues**: Deploy in the same region as your S3 bucket
3. **Existing Resources**: Check for naming conflicts with existing resources

## Security Considerations

- **Access Control**: CloudTrail logs contain sensitive information - implement proper IAM policies
- **Encryption**: Consider enabling S3 bucket encryption for additional security
- **Network Security**: Logs include source IP addresses for access pattern analysis
- **Compliance**: The solution helps meet audit and compliance requirements for data access tracking

## Cleanup

To remove all resources and stop charges:

1. Go to **CloudFormation** console
2. Select your stack
3. Click **Delete**
4. Confirm deletion

**Note**: S3 buckets with content may need to be emptied manually before stack deletion completes.

## Customization Options

The CloudFormation template can be modified to:

- **Add Custom Filtering**: Modify Lambda function to filter specific events
- **Change Log Format**: Customize the log entry structure
- **Add Alerting**: Integrate with SNS for real-time notifications
- **Extend Retention**: Modify lifecycle policies for longer retention
- **Add Encryption**: Enable KMS encryption for logs and archives

## Support and Monitoring

### Health Checks

Monitor these key metrics:
- CloudTrail delivery status
- Lambda function errors and duration
- CloudWatch log ingestion rate
- S3 storage usage for archives

### Alerts (Optional Enhancement)

Consider adding CloudWatch alarms for:
- Lambda function failures
- High error rates in S3 operations
- Unusual access patterns
- Cost thresholds

This solution provides comprehensive S3 access logging with both real-time monitoring and long-term archival capabilities, suitable for security auditing, compliance, and operational monitoring requirements.

### License
This solution is provided as-is for educational and operational purposes. Review and test thoroughly before deploying in production environments.
