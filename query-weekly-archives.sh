#!/bin/bash

# Weekly S3 Archive Query Script - Updated for CloudFormation Template v9
# This script queries weekly S3 archive files created by the logging solution

# Configuration - UPDATE THESE VALUES
BUCKET_NAME="your-bucket-name-here"  # CHANGE THIS to your actual monitored bucket name
ARCHIVE_BUCKET=""  # Will be auto-detected from CloudFormation stack
STACK_NAME="s3-access-logging-stack"  # CHANGE THIS to your actual stack name
REGION="us-east-1"  # Change this to your deployment region

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Weekly S3 Archive Query Script - CloudFormation Template v9"
    echo "=========================================================="
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -l, --list          List all available weekly archive files"
    echo "  -w, --week WEEK     Download and display specific week (format: YYYY-WWW)"
    echo "  -s, --summary WEEK  Show summary for specific week"
    echo "  -a, --all-summaries Show summaries for all weeks"
    echo "  -d, --download WEEK Download weekly file to current directory"
    echo "  -r, --recent        Show most recent week's data"
    echo "  -c, --check         Check archive bucket status and configuration"
    echo ""
    echo "Week Format: YYYY-WWW (e.g., 2024-W25 for week 25 of 2024)"
    echo ""
    echo "Examples:"
    echo "  $0 -c                    # Check archive bucket status"
    echo "  $0 -l                    # List all weekly archives"
    echo "  $0 -w 2024-W25           # Show logs for week 25 of 2024"
    echo "  $0 -s 2024-W25           # Show summary for week 25 of 2024"
    echo "  $0 -a                    # Show all weekly summaries"
    echo "  $0 -d 2024-W25           # Download week 25 file"
    echo "  $0 -r                    # Show most recent week"
    echo ""
    echo "Note: Make sure to update BUCKET_NAME, STACK_NAME, and REGION variables in this script"
}

# Function to get archive bucket name from CloudFormation
get_archive_bucket() {
    if [ -z "$ARCHIVE_BUCKET" ]; then
        echo -e "${YELLOW}Detecting archive bucket from CloudFormation stack...${NC}"
        
        ARCHIVE_BUCKET=$(aws cloudformation describe-stacks \
            --stack-name $STACK_NAME \
            --region $REGION \
            --query 'Stacks[0].Outputs[?OutputKey==`WeeklyArchiveBucket`].OutputValue' \
            --output text 2>/dev/null)
        
        if [ -z "$ARCHIVE_BUCKET" ] || [ "$ARCHIVE_BUCKET" = "None" ]; then
            echo -e "${RED}Error: Could not find archive bucket from CloudFormation stack${NC}"
            echo "Make sure:"
            echo "1. The stack '$STACK_NAME' exists and has been deployed successfully"
            echo "2. STACK_NAME variable matches your actual CloudFormation stack name"
            echo "3. REGION variable matches your deployment region"
            echo "4. AWS CLI is configured with proper credentials"
            echo ""
            echo "You can find your stack name with:"
            echo "  aws cloudformation list-stacks --region $REGION --query 'StackSummaries[?contains(StackName, \`s3\`) && StackStatus==\`CREATE_COMPLETE\`].[StackName]' --output table"
            exit 1
        fi
        
        echo -e "${GREEN}Found archive bucket: $ARCHIVE_BUCKET${NC}"
    fi
}

# Function to check archive bucket status
check_archive_bucket() {
    echo -e "${BLUE}Checking Archive Bucket Status:${NC}"
    echo "==============================="
    echo -e "${YELLOW}Stack Name:${NC} $STACK_NAME"
    echo -e "${YELLOW}Region:${NC} $REGION"
    echo -e "${YELLOW}Archive Bucket:${NC} $ARCHIVE_BUCKET"
    echo ""
    
    # Check if bucket exists and is accessible
    aws s3 ls s3://$ARCHIVE_BUCKET/ --region $REGION >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Cannot access archive bucket${NC}"
        echo "Make sure the CloudFormation stack has been deployed successfully"
        return 1
    fi
    
    # Check weekly-logs prefix
    echo -e "${BLUE}Weekly Logs Directory:${NC}"
    WEEKLY_COUNT=$(aws s3 ls s3://$ARCHIVE_BUCKET/weekly-logs/ --region $REGION 2>/dev/null | wc -l)
    echo "Weekly archive files found: $WEEKLY_COUNT"
    
    if [ "$WEEKLY_COUNT" -eq 0 ]; then
        echo -e "\n${YELLOW}No weekly archives found yet. This could mean:${NC}"
        echo "1. The solution was recently deployed and no full weeks have passed"
        echo "2. No S3 operations have been performed on the monitored bucket"
        echo "3. The Lambda function may not be processing logs correctly"
        echo ""
        echo "Weekly archives are created when:"
        echo "- S3 operations are performed on the monitored bucket"
        echo "- CloudTrail captures the events (15-20 minutes delay)"
        echo "- Lambda processes the CloudTrail logs"
        echo ""
        echo "Try performing some S3 operations and wait for processing:"
        echo "  aws s3 cp test.txt s3://$BUCKET_NAME/"
        echo "  aws s3 ls s3://$BUCKET_NAME/"
    else
        echo -e "\n${BLUE}Recent Weekly Archives:${NC}"
        aws s3 ls s3://$ARCHIVE_BUCKET/weekly-logs/ --region $REGION | tail -5
    fi
    
    # Check bucket policy and permissions
    echo -e "\n${BLUE}Bucket Configuration:${NC}"
    aws s3api get-bucket-versioning --bucket $ARCHIVE_BUCKET --region $REGION --query 'Status' --output text 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "Bucket versioning: Enabled"
    else
        echo "Could not check bucket versioning"
    fi
}

# Function to list all weekly archives
list_archives() {
    echo -e "${BLUE}Available Weekly Archives:${NC}"
    echo "=========================="
    
    aws s3 ls s3://$ARCHIVE_BUCKET/weekly-logs/ --region $REGION 2>/dev/null | \
    while read -r line; do
        # Extract filename and size
        filename=$(echo "$line" | awk '{print $4}')
        size=$(echo "$line" | awk '{print $3}')
        date=$(echo "$line" | awk '{print $1, $2}')
        
        if [ ! -z "$filename" ]; then
            week=$(basename "$filename" .json)
            # Convert size to human readable
            if [ "$size" -gt 1048576 ]; then
                size_hr=$(echo "scale=1; $size/1048576" | bc 2>/dev/null || echo "$size")
                size_hr="${size_hr}MB"
            elif [ "$size" -gt 1024 ]; then
                size_hr=$(echo "scale=1; $size/1024" | bc 2>/dev/null || echo "$size")
                size_hr="${size_hr}KB"
            else
                size_hr="${size}B"
            fi
            echo -e "${GREEN}Week: $week${NC} (Size: $size_hr, Modified: $date)"
        fi
    done
    
    # Show total count
    TOTAL_COUNT=$(aws s3 ls s3://$ARCHIVE_BUCKET/weekly-logs/ --region $REGION 2>/dev/null | wc -l)
    echo ""
    echo "Total weekly archives: $TOTAL_COUNT"
}

# Function to show summary for a specific week
show_summary() {
    local week=$1
    local temp_file="/tmp/weekly-log-$week.json"
    
    echo -e "${BLUE}Summary for Week $week:${NC}"
    echo "======================="
    
    # Download the file
    aws s3 cp s3://$ARCHIVE_BUCKET/weekly-logs/$week.json $temp_file --region $REGION --quiet 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Could not download weekly archive for $week${NC}"
        echo "Make sure the week format is correct (YYYY-WWW) and the file exists"
        echo "Use '$0 -l' to see available weeks"
        return 1
    fi
    
    # Extract and display summary
    python3 -c "
import json
import sys

try:
    with open('$temp_file', 'r') as f:
        data = json.load(f)
    
    summary = data.get('summary', {})
    
    print(f\"Week: {data.get('week', 'Unknown')}\")
    print(f\"Generated: {data.get('generated_at', 'Unknown')}\")
    print(f\"Total Events: {summary.get('total_events', 0)}\")
    print(f\"Error Count: {summary.get('error_count', 0)}\")
    print(f\"Unique Users: {summary.get('unique_users', 0)}\")
    print(f\"Unique IPs: {summary.get('unique_ips', 0)}\")
    print()
    
    print('Top Operations:')
    for op, count in summary.get('top_operations', {}).items():
        print(f'  {op}: {count}')
    print()
    
    print('Top Users:')
    for user, count in list(summary.get('top_users', {}).items())[:5]:
        print(f'  {user}: {count}')
    print()
    
    print('Top Source IPs:')
    for ip, count in list(summary.get('top_source_ips', {}).items())[:5]:
        print(f'  {ip}: {count}')
        
except Exception as e:
    print(f'Error processing file: {e}')
    sys.exit(1)
" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error processing weekly archive file${NC}"
    fi
    
    # Clean up temp file
    rm -f $temp_file
}

# Function to show all summaries
show_all_summaries() {
    echo -e "${BLUE}All Weekly Summaries:${NC}"
    echo "===================="
    
    # Get list of all weekly files
    aws s3 ls s3://$ARCHIVE_BUCKET/weekly-logs/ --region $REGION 2>/dev/null | \
    awk '{print $4}' | grep -E '\.json$' | sort | \
    while read filename; do
        if [ ! -z "$filename" ]; then
            week=$(basename "$filename" .json)
            echo -e "\n${YELLOW}--- $week ---${NC}"
            show_summary "$week"
        fi
    done
}

# Function to display full week data
show_week_data() {
    local week=$1
    local temp_file="/tmp/weekly-log-$week.json"
    
    echo -e "${BLUE}Full Data for Week $week:${NC}"
    echo "========================="
    
    # Download the file
    aws s3 cp s3://$ARCHIVE_BUCKET/weekly-logs/$week.json $temp_file --region $REGION --quiet 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Could not download weekly archive for $week${NC}"
        echo "Make sure the week format is correct (YYYY-WWW) and the file exists"
        echo "Use '$0 -l' to see available weeks"
        return 1
    fi
    
    # Display formatted logs
    python3 -c "
import json
from datetime import datetime

try:
    with open('$temp_file', 'r') as f:
        data = json.load(f)
    
    logs = data.get('logs', [])
    
    print(f\"Week: {data.get('week', 'Unknown')}\")
    print(f\"Total Events: {len(logs)}\")
    print('-' * 50)
    
    for i, log_entry in enumerate(logs):
        if i >= 50:  # Limit output for readability
            remaining = len(logs) - i
            print(f'... and {remaining} more events')
            print('Use -d option to download full file for detailed analysis')
            break
            
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
        
        print(f'Time: {formatted_time}')
        print(f'Operation: {operation} ({event_name})')
        print(f'User: {user_name}')
        print(f'Source IP: {source_ip}')
        print(f'Resource: s3://{bucket}/{key}')
        if error_code:
            print(f'Error: {error_code}')
        print('-' * 30)
        
except Exception as e:
    print(f'Error processing file: {e}')
" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error processing weekly archive file${NC}"
    fi
    
    # Clean up temp file
    rm -f $temp_file
}

# Function to get most recent week
show_recent() {
    echo -e "${BLUE}Most Recent Weekly Archive:${NC}"
    echo "=========================="
    
    # Get the most recent file
    recent_file=$(aws s3 ls s3://$ARCHIVE_BUCKET/weekly-logs/ --region $REGION 2>/dev/null | \
                  sort -k1,2 | tail -1 | awk '{print $4}')
    
    if [ -z "$recent_file" ]; then
        echo -e "${RED}No weekly archives found${NC}"
        echo "Use '$0 -c' to check the archive bucket status"
        return 1
    fi
    
    week=$(basename "$recent_file" .json)
    echo -e "${GREEN}Most recent week: $week${NC}"
    echo ""
    show_summary "$week"
}

# Check if configuration needs updating
if [ "$BUCKET_NAME" = "your-bucket-name-here" ]; then
    echo -e "${RED}Error: Please update the BUCKET_NAME variable in this script${NC}"
    echo "Edit this script and change BUCKET_NAME to your actual S3 bucket name"
    exit 1
fi

if [ "$STACK_NAME" = "s3-access-logging-stack" ]; then
    echo -e "${YELLOW}Warning: Using default STACK_NAME. Update if your stack has a different name${NC}"
fi

# Parse command line arguments
if [ $# -eq 0 ]; then
    usage
    exit 0
fi

# Get archive bucket name
get_archive_bucket

echo -e "${GREEN}S3 Weekly Archive Query - Template v9${NC}"
echo "====================================="
echo -e "${YELLOW}Archive Bucket:${NC} $ARCHIVE_BUCKET"
echo ""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -c|--check)
            check_archive_bucket
            exit 0
            ;;
        -l|--list)
            list_archives
            exit 0
            ;;
        -w|--week)
            if [ -z "$2" ]; then
                echo -e "${RED}Error: Week parameter required (format: YYYY-WWW)${NC}"
                exit 1
            fi
            show_week_data "$2"
            exit 0
            ;;
        -s|--summary)
            if [ -z "$2" ]; then
                echo -e "${RED}Error: Week parameter required (format: YYYY-WWW)${NC}"
                exit 1
            fi
            show_summary "$2"
            exit 0
            ;;
        -a|--all-summaries)
            show_all_summaries
            exit 0
            ;;
        -d|--download)
            if [ -z "$2" ]; then
                echo -e "${RED}Error: Week parameter required (format: YYYY-WWW)${NC}"
                exit 1
            fi
            echo -e "${YELLOW}Downloading weekly archive for $2...${NC}"
            aws s3 cp s3://$ARCHIVE_BUCKET/weekly-logs/$2.json ./$2.json --region $REGION
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Downloaded: $2.json${NC}"
                echo "File size: $(ls -lh $2.json | awk '{print $5}')"
            else
                echo -e "${RED}Error downloading file${NC}"
                echo "Make sure the week format is correct (YYYY-WWW) and the file exists"
                echo "Use '$0 -l' to see available weeks"
            fi
            exit 0
            ;;
        -r|--recent)
            show_recent
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option $1${NC}"
            usage
            exit 1
            ;;
    esac
done
