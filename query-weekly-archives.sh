#!/bin/bash

# Weekly S3 Archive Query Script

# Configuration
BUCKET_NAME="your-bucket-name-here"  # CHANGE THIS to your actual bucket name
ARCHIVE_BUCKET=""  # Will be auto-detected from CloudFormation stack
STACK_NAME="s3-access-logging-stack"
REGION="us-east-1"  # Change this to your region

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -l, --list          List all available weekly archive files"
    echo "  -w, --week WEEK     Download and display specific week (format: YYYY-WWW)"
    echo "  -s, --summary WEEK  Show summary for specific week"
    echo "  -a, --all-summaries Show summaries for all weeks"
    echo "  -d, --download WEEK Download weekly file to current directory"
    echo "  -r, --recent        Show most recent week's data"
    echo ""
    echo "Examples:"
    echo "  $0 -l                    # List all weekly archives"
    echo "  $0 -w 2024-W25           # Show logs for week 25 of 2024"
    echo "  $0 -s 2024-W25           # Show summary for week 25 of 2024"
    echo "  $0 -a                    # Show all weekly summaries"
    echo "  $0 -d 2024-W25           # Download week 25 file"
    echo "  $0 -r                    # Show most recent week"
}

# Function to get archive bucket name from CloudFormation
get_archive_bucket() {
    if [ -z "$ARCHIVE_BUCKET" ]; then
        ARCHIVE_BUCKET=$(aws cloudformation describe-stacks \
            --stack-name $STACK_NAME \
            --region $REGION \
            --query 'Stacks[0].Outputs[?OutputKey==`WeeklyArchiveBucket`].OutputValue' \
            --output text 2>/dev/null)
        
        if [ -z "$ARCHIVE_BUCKET" ]; then
            echo -e "${RED}Error: Could not find archive bucket from CloudFormation stack${NC}"
            echo "Make sure the stack '$STACK_NAME' exists and has been deployed successfully"
            exit 1
        fi
    fi
}

# Function to list all weekly archives
list_archives() {
    echo -e "${BLUE}Available Weekly Archives:${NC}"
    echo "=========================="
    
    aws s3 ls s3://$ARCHIVE_BUCKET/weekly-logs/ --region $REGION | \
    while read -r line; do
        # Extract filename and size
        filename=$(echo "$line" | awk '{print $4}')
        size=$(echo "$line" | awk '{print $3}')
        date=$(echo "$line" | awk '{print $1, $2}')
        
        if [ ! -z "$filename" ]; then
            week=$(basename "$filename" .json)
            echo -e "${GREEN}Week: $week${NC} (Size: $size, Modified: $date)"
        fi
    done
}

# Function to show summary for a specific week
show_summary() {
    local week=$1
    local temp_file="/tmp/weekly-log-$week.json"
    
    echo -e "${BLUE}Summary for Week $week:${NC}"
    echo "======================="
    
    # Download the file
    aws s3 cp s3://$ARCHIVE_BUCKET/weekly-logs/$week.json $temp_file --region $REGION --quiet
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Could not download weekly archive for $week${NC}"
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
"
    
    # Clean up temp file
    rm -f $temp_file
}

# Function to show all summaries
show_all_summaries() {
    echo -e "${BLUE}All Weekly Summaries:${NC}"
    echo "===================="
    
    # Get list of all weekly files
    aws s3 ls s3://$ARCHIVE_BUCKET/weekly-logs/ --region $REGION | \
    awk '{print $4}' | grep -E '\.json$' | \
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
    aws s3 cp s3://$ARCHIVE_BUCKET/weekly-logs/$week.json $temp_file --region $REGION --quiet
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Could not download weekly archive for $week${NC}"
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
    
    for log_entry in logs:
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
"
    
    # Clean up temp file
    rm -f $temp_file
}

# Function to get most recent week
show_recent() {
    echo -e "${BLUE}Most Recent Weekly Archive:${NC}"
    echo "=========================="
    
    # Get the most recent file
    recent_file=$(aws s3 ls s3://$ARCHIVE_BUCKET/weekly-logs/ --region $REGION | \
                  sort -k1,2 | tail -1 | awk '{print $4}')
    
    if [ -z "$recent_file" ]; then
        echo -e "${RED}No weekly archives found${NC}"
        return 1
    fi
    
    week=$(basename "$recent_file" .json)
    echo -e "${GREEN}Most recent week: $week${NC}"
    echo ""
    show_summary "$week"
}

# Parse command line arguments
if [ $# -eq 0 ]; then
    usage
    exit 0
fi

# Get archive bucket name
get_archive_bucket

echo -e "${GREEN}S3 Weekly Archive Query${NC}"
echo "======================="
echo -e "${YELLOW}Archive Bucket:${NC} $ARCHIVE_BUCKET"
echo ""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -l|--list)
            list_archives
            exit 0
            ;;
        -w|--week)
            if [ -z "$2" ]; then
                echo -e "${RED}Error: Week parameter required${NC}"
                exit 1
            fi
            show_week_data "$2"
            exit 0
            ;;
        -s|--summary)
            if [ -z "$2" ]; then
                echo -e "${RED}Error: Week parameter required${NC}"
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
                echo -e "${RED}Error: Week parameter required${NC}"
                exit 1
            fi
            echo -e "${YELLOW}Downloading weekly archive for $2...${NC}"
            aws s3 cp s3://$ARCHIVE_BUCKET/weekly-logs/$2.json ./$2.json --region $REGION
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Downloaded: $2.json${NC}"
            else
                echo -e "${RED}Error downloading file${NC}"
            fi
            exit 0
            ;;
        -r|--recent)
            show_recent
            exit 0
            ;;
        *)
            echo "Unknown option $1"
            usage
            exit 1
            ;;
    esac
done
