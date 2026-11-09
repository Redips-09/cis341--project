#!/bin/bash

##config file validation functions to check variable correctness for main script
## author hamza

validate_positive_int(){

local value="$1"

if [[ -n "$value" && "$value" != *[!0-9]* && "$value" == *[1-9]* ]]; then
	return 0
else
	return 7
fi
}

validate_config(){

for required in AUDIT_DIR LOG_FILE SCAN_INTERVAL_SECONDS MAX_DISK_USAGE RETENTION_DAYS CLEANUP_INTERVAL_DAYS LOG_LEVEL DEFAULT_MODE; do
    if [[ -z "${!required}" ]]; then
        echo "Missing required configuration value: $required" >&2
        return 7
    fi
done

if validate_positive_int "$SCAN_INTERVAL_SECONDS"; then
	echo "Scan interval is valid"
else
	echo "Scan interval is invalid" >&2
	return 7
fi

if validate_positive_int "$MAX_DISK_USAGE"; then
        echo "Max disk usage is valid"
else
        echo "Max disk usage is invalid" >&2
        return 7 
fi

if validate_positive_int "$RETENTION_DAYS"; then
        echo "Retention Days is valid"
else
        echo "Retention Days is invalid" >&2
        return 7 
fi


if validate_positive_int "$CLEANUP_INTERVAL_DAYS"; then
        echo "cleanup interval is valid"
else
        echo "cleanup interval is invalid" >&2
        return 7 
fi

if [[ "$LOG_LEVEL" != "ERROR" && "$LOG_LEVEL" != "WARN" && "$LOG_LEVEL" != "INFO" && "$LOG_LEVEL" != "DEBUG" && "$LOG_LEVEL" != "WARNING" ]]; then
	echo "Invalid Log level" >&2
	return 7
fi

if [[ "$DEFAULT_MODE" != "daemon" && "$DEFAULT_MODE" != "run" ]]; then
	echo "Invalid run mode, change DEFAULT_MODE to run or daemon" >&2
	return 7
fi

validate_audit_dir || return $?

return 0
}

# Workspace failures use the project's INVALID_WORKSPACE exit code (4).
validate_audit_dir() {
    if [[ ! -d "$AUDIT_DIR" ]]; then
        echo "Invalid audit workspace: $AUDIT_DIR is missing or not a directory" >&2
        return 4
    fi
    if [[ ! -w "$AUDIT_DIR" || ! -x "$AUDIT_DIR" ]]; then
        echo "Invalid audit workspace: $AUDIT_DIR is not writable/searchable" >&2
        return 4
    fi
    return 0
}

