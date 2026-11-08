#!/bin/bash

## scanner function to scan system and create .audit files
## scans for health and security data
## author hamza


generate_audit(){

local TIMESTAMP
local REPORT_FILE

if [ ! -d "$AUDIT_DIR" ]; then
    log_exception 4 "Audit folder $AUDIT_DIR does not exist"
    exit 4
fi 

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$AUDIT_DIR/scan_${TIMESTAMP}.audit"

echo "=================HOSTNAME===================" > "$REPORT_FILE"
hostname >> "$REPORT_FILE"
echo "=================UPTIME===================" >> "$REPORT_FILE"
uptime >> "$REPORT_FILE"
echo "=================RAM===================" >> "$REPORT_FILE"
free -h >> "$REPORT_FILE"
echo "=================DISK USAGE===================" >> "$REPORT_FILE"
df -h >> "$REPORT_FILE"
echo "=================NETWORK CONNECTIONS===================" >> "$REPORT_FILE"
ss -tulpn >> "$REPORT_FILE"
echo "=================PROCESSES===================" >> "$REPORT_FILE"
ps aux >> "$REPORT_FILE"
echo "=================CURRENT LOGINS===================" >> "$REPORT_FILE"
who >> "$REPORT_FILE"
echo "=================LOGINS===================" >> "$REPORT_FILE"
last -n 10 >> "$REPORT_FILE"

log_file_dump "$REPORT_FILE"

}
