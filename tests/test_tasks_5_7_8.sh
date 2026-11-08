#!/usr/bin/env bash
#===============================================================================
# File    : tests/test_tasks_5_7_8.sh
# Project : CIS 341 Fall 2026 - sysaudit
# Author  : Felix Tu
# Date    : 2026-10-30
#
# Tests for tasks 5, 7 and 8. Makes a temporary test folder, so it does not
# need root and does not touch /var/log or the real audit folder.
# Usage (from the repo folder): bash tests/test_tasks_5_7_8.sh
# Exit status = number of failed tests.
#===============================================================================

ROOT="$(cd "$(dirname "$0")/.." && pwd)"        # the repo folder
TEST_DIR="$(mktemp -d)"
LOG="$TEST_DIR/sysaudit_daemon.log"
CFG="$TEST_DIR/sysaudit.cfg"
WS="$TEST_DIR/audit"
ERR="$TEST_DIR/stderr.txt"
pass=0
fail=0

# result EXIT_STATUS "description"
result() {
    if [ "$1" -eq 0 ]; then
        echo "PASS  $2"
        pass=$((pass + 1))
    else
        echo "FAIL  $2"
        fail=$((fail + 1))
    fi
}

# Write a test config. Extra KEY=VALUE arguments are added at the end and
# override the defaults above them.
make_config() {
    {
        echo "LOG_FILE=$LOG"
        echo "LOG_LEVEL=INFO"
        echo "AUDIT_DIR=$WS"
        echo "ARCHIVE_EXTENSIONS=tar.gz,zip"
        echo "MAX_DISK_USAGE=100"
        for line in "$@"; do echo "$line"; done
    } > "$CFG"
}

# Start each test with an empty log and an empty audit folder.
reset() {
    rm -rf "$WS" "$LOG"
    mkdir -p "$WS"
}

# Run commands in a subshell with all three scripts loaded.
# STDERR is saved in $ERR.
run() {
    (
        source "$ROOT/sysaudit_logger.sh"
        source "$ROOT/sysaudit_summary.sh"
        source "$ROOT/sysaudit_ceiling.sh"
        load_config "$CFG" || exit $?
        init_log || exit $?
        "$@"
    ) 2> "$ERR"
}

echo "--- Task 5: log file ---"
reset; make_config
echo "some report data" > "$WS/scan_1.audit"
run log_scan_start 1
run log_file_dump "$WS/scan_1.audit"
run log_sleep_change 60 30
run log_exception 4 "workspace missing"
[ -f "$LOG" ];                                                         result $? "log file is created"
grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8} \[INFO\]' "$LOG";     result $? "lines have a timestamp and [INFO]"
grep -q 'Scan loop #1 started' "$LOG";                                 result $? "scan loop start is logged"
grep -q 'Saved data file .*scan_1.audit (17 bytes)' "$LOG";            result $? "file dump is logged with its size"
grep -q 'Sleep interval changed from 60 to 30' "$LOG";                 result $? "sleep change is logged"
grep -q '\[ERROR\] .*exit code 4: workspace missing' "$LOG";           result $? "exception is logged as [ERROR]"
grep -q 'workspace missing' "$ERR";                                    result $? "[ERROR] is also printed to STDERR"

reset; make_config
run log_msg DEBUG "hidden message"
! grep -q 'hidden message' "$LOG";                                     result $? "DEBUG is skipped when LOG_LEVEL=INFO"

reset; rm -f "$CFG"
run true; code=$?
[ "$code" -eq 3 ];                                                     result $? "missing config file returns 3"

reset; make_config "THIS LINE IS WRONG"
run true; code=$?
[ "$code" -eq 7 ];                                                     result $? "bad config line returns 7"

reset; touch "$TEST_DIR/a_file"; make_config "LOG_FILE=$TEST_DIR/a_file/log.txt"
run true; code=$?
[ "$code" -eq 6 ];                                                     result $? "log that cannot be written returns 6"

# The team's real sysaudit.cfg has "# comments" after the values.
values=$( source "$ROOT/sysaudit_logger.sh"
          load_config "$ROOT/sysaudit.cfg" && echo "$LOG_FILE|$MAX_DISK_USAGE|$ARCHIVE_EXTENSIONS" )
[ "$values" = "/var/log/sysaudit_daemon.log|100|tar.gz,zip" ];        result $? "team's sysaudit.cfg loads (comments removed)"

values=$( source "$ROOT/sysaudit.cfg" 2>/dev/null && echo "$MAX_DISK_USAGE|$ARCHIVE_EXTENSIONS" )
[ "$values" = "100|tar.gz,zip" ];                                      result $? "team's sysaudit.cfg still works with 'source'"

echo "--- Task 7: archive summary ---"
reset; make_config
head -c 3000  /dev/zero > "$WS/audit_2026-10-20.tar.gz"
head -c 10240 /dev/zero > "$WS/audit_2026-10-27.tar.gz"
head -c 5000  /dev/zero > "$WS/audit_2026-10-23.zip"
head -c 50000 /dev/zero > "$WS/scan_99.audit"          # not an archive
touch -t 202610270000.04 "$WS/audit_2026-10-27.tar.gz"   # -t = local time on GNU and uutils
run archive_summary; code=$?
[ "$code" -eq 0 ];                                                     result $? "summary returns 0"
grep -q 'Archive summary: 3 archives' "$LOG";                          result $? "counts only the 3 archives"
grep -q 'largest is audit_2026-10-27.tar.gz' "$LOG";                   result $? "finds the largest archive"
grep -q '(10240 bytes' "$LOG";                                         result $? "logs its exact size in bytes"
grep -q 'modified 2026-10-27 00:00:04' "$LOG";                         result $? "logs its modification time"

reset; make_config
run archive_summary
grep -q 'Archive summary: 0 archives' "$LOG";                          result $? "empty folder gives 0 archives"

reset; make_config "AUDIT_DIR=$TEST_DIR/missing"
run archive_summary; code=$?
[ "$code" -eq 4 ];                                                     result $? "missing audit folder returns 4"

echo "--- Task 8: disk ceiling ---"
reset; make_config
head -c 2097152 /dev/zero > "$WS/big.tar.gz"            # 2 MB
run check_disk_ceiling; code=$?
[ "$code" -eq 0 ];                                                     result $? "2 MB under a 100 MB ceiling returns 0"
grep -q '\[INFO\] .*Disk usage OK' "$LOG";                             result $? "OK result is logged as [INFO]"

reset; make_config "MAX_DISK_USAGE=1"
head -c 2097152 /dev/zero > "$WS/big.tar.gz"
run check_disk_ceiling; code=$?
[ "$code" -eq 5 ];                                                     result $? "2 MB over a 1 MB ceiling returns 5"
grep -q '\[WARNING\] .*Disk ceiling reached' "$LOG";                   result $? "[WARNING] is written to the log"
grep -q 'Disk ceiling reached' "$ERR";                                 result $? "[WARNING] is also printed to STDERR"

reset; make_config "MAX_DISK_USAGE=1" "LOG_LEVEL=ERROR"
head -c 2097152 /dev/zero > "$WS/big.tar.gz"
run check_disk_ceiling
grep -q '\[WARNING\] .*Disk ceiling reached' "$LOG";                   result $? "[WARNING] is still logged when LOG_LEVEL=ERROR"

reset; make_config "MAX_DISK_USAGE=lots"
run check_disk_ceiling; code=$?
[ "$code" -eq 7 ];                                                     result $? "non-number ceiling returns 7"

reset; make_config "AUDIT_DIR=$TEST_DIR/missing"
run check_disk_ceiling; code=$?
[ "$code" -eq 4 ];                                                     result $? "missing audit folder returns 4"

rm -rf "$TEST_DIR"
echo "-----------------------------"
echo "Passed: $pass   Failed: $fail"
exit "$fail"
