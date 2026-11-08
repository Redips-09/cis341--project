#!/usr/bin/env bash
#===============================================================================
# File    : sysaudit_logger.sh
# Project : CIS 341 Fall 2026 - System Health Monitor & Security Auditing Daemon
# Task    : #5 Isolated Self-Monitoring Transcript Engine
# Author  : Felix Tu
# Date    : 2026-10-30
#
# What it does:
#   Writes the daemon's own log file (LOG_FILE in sysaudit.cfg, normally
#   /var/log/sysaudit_daemon.log). Every line has a timestamp and a level:
#       2026-10-30 00:00:01 [INFO] sysaudit[2211]: Scan loop #1 started
#   Levels: [ERROR] [WARNING] [WARN] [INFO] [DEBUG]
#   ERROR and WARNING lines are also printed to STDERR.
#
# Functions:
#   load_config FILE           read KEY=VALUE lines from sysaudit.cfg
#   init_log                   create/check the log file, write a start line
#   log_msg LEVEL MESSAGE      write one line to the log
#   log_scan_start NUMBER      "scan loop started"
#   log_file_dump FILE         "data file saved" (with its size)
#   log_sleep_change OLD NEW   "sleep interval changed"
#   log_exception CODE TEXT    "handled exception" (written as ERROR)
#
# Config keys used: LOG_FILE, LOG_LEVEL (ERROR, WARN, INFO or DEBUG)
#
# Return codes: 0 ok, 3 config file or LOG_FILE missing,
#               6 log file not writable, 7 bad line in config
#
# How to use it in the main script (sysaudit.sh):
#   source "$SCRIPT_DIR/sysaudit_logger.sh"      # load this file first
#   load_config "$CONFIG_FILE" || exit $?
#   init_log || exit $?
#   log_scan_start 1
#   log_exception 4 "workspace folder is missing"
#
# Requires: bash 4.2 or newer, date, wc, whoami
#===============================================================================

# Read the config file one line at a time (while read, p.208).
# Each line looks like KEY=VALUE with no spaces around "=".
# A "# comment" after the value is allowed, so values cannot contain "#".
load_config() {
    local cfg="$1"
    local key value bad=0

    if [ ! -f "$cfg" ]; then
        echo "sysaudit: config file '$cfg' not found" >&2
        return 3
    fi

    while IFS='=' read -r key value; do
        case "$key" in
            ''|\#*) continue ;;                 # skip blank lines and comments
        esac
        if [[ ! "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
            echo "sysaudit: bad line in $cfg: $key" >&2
            bad=1
            continue
        fi
        value="${value%%#*}"                     # drop a comment at the end of the line
        read -r value <<< "$value"               # trim spaces around the value
        declare -g "$key=$value"                 # make it a global variable
    done < "$cfg"

    if [ "$bad" -eq 1 ]; then
        return 7
    fi
    return 0
}

# Turn a level name into a number, like logMsg() on p.206.
# 0 is the most severe, 3 the least.
level_number() {
    case "$1" in
        ERROR)        echo 0 ;;
        WARNING|WARN) echo 1 ;;
        INFO)         echo 2 ;;
        DEBUG)        echo 3 ;;
        *)            echo 2 ;;
    esac
}

log_msg() {
    local level="$1"
    shift
    local message="$*"
    local line

    # Skip messages that are less important than LOG_LEVEL (p.206).
    # WARNING is the high-priority disk-ceiling flag (task 8), so it is never skipped.
    if [ "$level" != "WARNING" ] && [ "$(level_number "$level")" -gt "$(level_number "${LOG_LEVEL:-INFO}")" ]; then
        return 0
    fi

    line="$(date '+%Y-%m-%d %H:%M:%S') [$level] sysaudit[$$]: $message"
    echo "$line" >> "$LOG_FILE"

    # Errors and warnings also go to STDERR (p.188)
    if [ "$level" = "ERROR" ] || [ "$level" = "WARNING" ]; then
        echo "$line" >&2
    fi
}

init_log() {
    if [ -z "$LOG_FILE" ]; then
        echo "sysaudit: LOG_FILE is not set in sysaudit.cfg" >&2
        return 3
    fi

    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    touch "$LOG_FILE" 2>/dev/null

    if [ ! -w "$LOG_FILE" ]; then
        echo "sysaudit: cannot write to log file $LOG_FILE" >&2
        return 6
    fi

    log_msg INFO "Log started (user $(whoami))"
    return 0
}

# --- the four events task #5 asks for ----------------------------------------

log_scan_start() {
    log_msg INFO "Scan loop #$1 started"
}

log_file_dump() {
    if [ -f "$1" ]; then
        log_msg INFO "Saved data file $1 ($(wc -c < "$1") bytes)"
    else
        log_msg WARN "Data file $1 was not found after saving"
    fi
}

log_sleep_change() {
    log_msg INFO "Sleep interval changed from $1 to $2 seconds"
}

log_exception() {
    log_msg ERROR "Exception with exit code $1: $2"
}
