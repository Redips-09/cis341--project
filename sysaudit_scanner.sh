#!/bin/bash

## scanner function to scan system and create .audit files
## scans for health and security data
## author hamza


generate_audit(){

local TIMESTAMP
local REPORT_FILE

if [ ! -d "$AUDIT_DIR" ] || [ ! -w "$AUDIT_DIR" ] || [ ! -x "$AUDIT_DIR" ]; then
    log_exception 4 "Audit folder $AUDIT_DIR is missing or inaccessible"
    return 4
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$AUDIT_DIR/scan_${TIMESTAMP}.audit"

if ! (
    set -e
    echo "=================HOSTNAME==================="
    hostname
    echo "=================UPTIME==================="
    uptime
    echo "=================RAM==================="
    free -h
    echo "=================DISK USAGE==================="
    df -h
    echo "=================NETWORK CONNECTIONS==================="
    ss -tulpn
    echo "=================PROCESSES==================="
    ps aux
    echo "=================CURRENT LOGINS==================="
    who
    echo "=================LOGINS==================="
    last -n 10
) > "$REPORT_FILE"; then
    log_exception 1 "Failed to create or complete audit report $REPORT_FILE"
    
    if [ -f "$REPORT_FILE" ]; then
        rm -f -- "$REPORT_FILE" || log_exception 1 "Could not remove incomplete report $REPORT_FILE"
    fi
    return 1
fi

log_file_dump "$REPORT_FILE"
return 0

}
