#!/bin/bash

# S3 Access Log Query Script - Updated for CloudFormation Template v9
# This script queries CloudWatch Logs for formatted S3 access events

# Configuration - UPDATE THESE VALUES
BUCKET_NAME="your-bucket-name-here"  # CHANGE THIS to your actual monitored bucket name
LOG_GROUP="/aws/s3/$BUCKET_NAME/access-logs"
REGION="us-east-1"  # Change this to your deployment region

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "S3 Access Log Query Script - CloudFormation Template v9"
    echo "======================================================"
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -t, --time HOURS    Show logs from last N hours (default: 1)"
    echo "  -u, --user USER     Filter by user name"
    echo "  -o, --operation OP  Filter by operation (READ, CREATE/UPDATE, DELETE)"
    echo "  -k, --key KEY       Filter by S3 object key"
    echo "  -i, --ip IP         Filter by source IP address"
    echo "  -e, --errors        Show only error events"
    echo "  -s, --summary       Show summary statistics"
    echo "  -c, --check         Check if log group exists and is receiving data"
    echo ""
    echo "Examples:"
    echo "  $0 -c                       # Check log group status"
    echo "  $0 -t 24                    # Show logs from last 24 hours"
    echo "  $0 -u john.doe              # Show logs for user john.doe"
    echo "  $0 -o DELETE                # Show all delete operations"
    echo "  $0 -k \"important-file.txt\" # Show logs for specific file"
    echo "  $0 -e                       # Show only errors"
    echo "  $0 -s                       # Show summary statistics"
    echo ""
    echo "Note: Make sure to update BUCKET_NAME and REGION variables in this script"
}

# Function to check log group status
check_log_group() {
    echo -e "${BLUE}Checking Log Group Status:${NC}"
    echo "=========================="
    echo -e "${YELLOW}Log Group:${NC} $LOG_GROUP"
    echo -e "${YELLOW}Region:${NC} $REGION"
    echo ""
    
    # Check if log group exists
    aws logs describe-log-groups \
        --log-group-name-prefix "$LOG_GROUP" \
        --region "$REGION" \
        --query 'logGroups[0]' \
        --output table 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Log group not found or AWS CLI not configured${NC}"
        echo "Make sure:"
        echo "1. CloudFormation stack has been deployed successfully"
        echo "2. BUCKET_NAME variable matches your monitored bucket"
        echo "3. REGION variable matches your deployment region"
        echo "4. AWS CLI is configured with proper credentials"
        return 1
    fi
    
    # Check recent log streams
    echo -e "\n${BLUE}Recent Log Streams:${NC}"
    aws logs describe-log-streams \
        --log-group-name "$LOG_GROUP" \
        --region "$REGION" \
        --order-by LastEventTime \
        --descending \
        --max-items 5 \
        --query 'logStreams[*].[logStreamName,lastEventTime,lastIngestionTime]' \
        --output table
    
    # Check for recent events
    echo -e "\n${BLUE}Recent Event Count:${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        START_TIME=$(date -v-1H +%s)000
    else
        # Linux
        START_TIME=$(date -d "1 hour ago" +%s)000
    fi
    
    EVENT_COUNT=$(aws logs filter-log-events \
        --log-group-name "$LOG_GROUP" \
        --start-time "$START_TIME" \
        --region "$REGION" \
        --query 'length(events)' \
        --output text 2>/dev/null)
    
    echo "Events in last hour: ${EVENT_COUNT:-0}"
    
    if [ "${EVENT_COUNT:-0}" -eq 0 ]; then
        echo -e "\n${YELLOW}No recent events found. This could mean:${NC}"
        echo "1. No S3 operations have been performed on the monitored bucket"
        echo "2. CloudTrail data events take 15-20 minutes to appear"
        echo "3. The CloudFormation stack may not be fully functional"
        echo ""
        echo "Try performing an S3 operation and wait 20 minutes:"
        echo "  aws s3 cp test.txt s3://$BUCKET_NAME/"
    fi
}

# Default values
HOURS=1
USER_FILTER=""
OPERATION_FILTER=""
KEY_FILTER=""
IP_FILTER=""
ERRORS_ONLY=false
SHOW_SUMMARY=false
CHECK_STATUS=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -c|--check)
            CHECK_STATUS=true
            shift
            ;;
        -t|--time)
            HOURS="$2"
            shift 2
            ;;
        -u|--user)
            USER_FILTER="$2"
            shift 2
            ;;
        -o|--operation)
            OPERATION_FILTER="$2"
            shift 2
            ;;
        -k|--key)
            KEY_FILTER="$2"
            shift 2
            ;;
        -i|--ip)
            IP_FILTER="$2"
            shift 2
            ;;
        -e|--errors)
            ERRORS_ONLY=true
            shift
            ;;
        -s|--summary)
            SHOW_SUMMARY=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Check if configuration needs updating
if [ "$BUCKET_NAME" = "your-bucket-name-here" ]; then
    echo -e "${RED}Error: Please update the BUCKET_NAME variable in this script${NC}"
    echo "Edit this script and change BUCKET_NAME to your actual S3 bucket name"
    exit 1
fi

# Handle check status option
if [ "$CHECK_STATUS" = true ]; then
    check_log_group
    exit 0
fi

# Calculate start time
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    START_TIME=$(date -v-${HOURS}H +%s)000
else
    # Linux
    START_TIME=$(date -d "$HOURS hours ago" +%s)000
fi

echo -e "${GREEN}S3 Access Log Query - Template v9${NC}"
echo "=================================="
echo -e "${YELLOW}Log Group:${NC} $LOG_GROUP"
echo -e "${YELLOW}Time Range:${NC} Last $HOURS hour(s)"

# Build filter pattern
FILTER_PATTERN=""
if [ "$USER_FILTER" != "" ]; then
    FILTER_PATTERN="$FILTER_PATTERN \"$USER_FILTER\""
fi
if [ "$OPERATION_FILTER" != "" ]; then
    FILTER_PATTERN="$FILTER_PATTERN \"$OPERATION_FILTER\""
fi
if [ "$KEY_FILTER" != "" ]; then
    FILTER_PATTERN="$FILTER_PATTERN \"$KEY_FILTER\""
fi
if [ "$IP_FILTER" != "" ]; then
    FILTER_PATTERN="$FILTER_PATTERN \"$IP_FILTER\""
fi
if [ "$ERRORS_ONLY" = true ]; then
    FILTER_PATTERN="$FILTER_PATTERN \"error\""
fi

echo -e "${YELLOW}Filters:${NC} $FILTER_PATTERN"
echo ""

if [ "$SHOW_SUMMARY" = true ]; then
    echo -e "${BLUE}Summary Statistics:${NC}"
    echo "==================="
    
    # Get all logs and process them
    aws logs filter-log-events \
        --log-group-name "$LOG_GROUP" \
        --start-time "$START_TIME" \
        --region "$REGION" \
        --output text \
        --query 'events[*].message' 2>/dev/null | \
    python3 -c "
import json
import sys
from collections import Counter

operations = Counter()
users = Counter()
ips = Counter()
errors = 0
total = 0

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        log_entry = json.loads(line)
        total += 1
        
        # Count operations
        operation = log_entry.get('operation', 'Unknown')
        operations[operation] += 1
        
        # Count users
        user = log_entry.get('who', {}).get('user_name', 'Unknown')
        users[user] += 1
        
        # Count IPs
        ip = log_entry.get('who', {}).get('source_ip', 'Unknown')
        ips[ip] += 1
        
        # Count errors
        if log_entry.get('response', {}).get('error_code'):
            errors += 1
            
    except json.JSONDecodeError:
        continue

print(f'Total Events: {total}')
print(f'Errors: {errors}')
print()
print('Top Operations:')
for op, count in operations.most_common(5):
    print(f'  {op}: {count}')
print()
print('Top Users:')
for user, count in users.most_common(5):
    print(f'  {user}: {count}')
print()
print('Top Source IPs:')
for ip, count in ips.most_common(5):
    print(f'  {ip}: {count}')
"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error querying logs. Check your configuration and try: $0 -c${NC}"
    fi
else
    echo -e "${BLUE}Recent S3 Access Events:${NC}"
    echo "======================="
    
    # Query CloudWatch Logs
    aws logs filter-log-events \
        --log-group-name "$LOG_GROUP" \
        --start-time "$START_TIME" \
        --filter-pattern "$FILTER_PATTERN" \
        --region "$REGION" \
        --output text \
        --query 'events[*].message' 2>/dev/null | \
    python3 -c "
import json
import sys
from datetime import datetime

event_count = 0
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        log_entry = json.loads(line)
        event_count += 1
        
        # Extract key information
        timestamp = log_entry.get('timestamp', '')
        operation = log_entry.get('operation', 'Unknown')
        event_name = log_entry.get('event_name', '')
        user_name = log_entry.get('who', {}).get('user_name', 'Unknown')
        source_ip = log_entry.get('who', {}).get('source_ip', 'Unknown')
        bucket = log_entry.get('what', {}).get('bucket', '')
        key = log_entry.get('what', {}).get('key', '')
        error_code = log_entry.get('response', {}).get('error_code', '')
        
        # Format timestamp
        if timestamp:
            try:
                dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                formatted_time = dt.strftime('%Y-%m-%d %H:%M:%S UTC')
            except:
                formatted_time = timestamp
        else:
            formatted_time = 'Unknown'
        
        # Print formatted log entry
        print(f'Time: {formatted_time}')
        print(f'Operation: {operation} ({event_name})')
        print(f'User: {user_name}')
        print(f'Source IP: {source_ip}')
        print(f'Resource: s3://{bucket}/{key}')
        if error_code:
            print(f'Error: {error_code}')
        print('-' * 50)
        
    except json.JSONDecodeError as e:
        print(f'Error parsing log entry: {e}')
        continue

if event_count == 0:
    print('No events found for the specified criteria.')
    print('Try:')
    print('  - Increasing the time range with -t option')
    print('  - Removing filters to see all events')
    print('  - Running with -c option to check log group status')
"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error querying logs. Check your configuration and try: $0 -c${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Query completed${NC}"
echo "Tip: Use '$0 -c' to check log group status and recent activity"
