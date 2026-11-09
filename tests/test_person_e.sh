#!/bin/bash

# CIS 341 - Person E
# Automated QA Testing Suite

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

passed=0
failed=0

check_test() {
    local actual="$1"
    local expected="$2"
    local description="$3"

    if [ "$actual" -eq "$expected" ]; then
        echo "PASS: $description"
        passed=$((passed + 1))
    else
        echo "FAIL: $description (expected $expected, got $actual)"
        failed=$((failed + 1))
    fi
}

echo "=== CIS 341 - Person E Test Suite ==="

# Test 1: No arguments
bash "$ROOT/sysaudit.sh" >/dev/null 2>&1
check_test "$?" 0 "No arguments"

# Test 2: Help option
bash "$ROOT/sysaudit.sh" --help >/dev/null 2>&1
check_test "$?" 0 "Help option"

# Test 3: Invalid argument
bash "$ROOT/sysaudit.sh" --invalid >/dev/null 2>&1
check_test "$?" 1 "Invalid argument"


echo "--- Configuration Tests ---"

# Test 4: Missing configuration file
bash -c '
    source "$1/sysaudit_logger.sh"
    load_config "/tmp/cis341_nonexistent_config_12345.cfg"
' _ "$ROOT" >/dev/null 2>&1

check_test "$?" 3 "Missing configuration returns exit code 3"

# Test 5: Valid configuration
TEMP_CFG=$(mktemp)
printf 'LOG_LEVEL=INFO\nMAX_DISK_USAGE=100\n' > "$TEMP_CFG"

bash -c '
    source "$1/sysaudit_logger.sh"
    load_config "$2"
' _ "$ROOT" "$TEMP_CFG" >/dev/null 2>&1

check_test "$?" 0 "Valid configuration loads successfully"

# Test 6: Malformed configuration
printf 'THIS LINE IS INVALID\n' > "$TEMP_CFG"

bash -c '
    source "$1/sysaudit_logger.sh"
    load_config "$2"
' _ "$ROOT" "$TEMP_CFG" >/dev/null 2>&1

check_test "$?" 7 "Malformed configuration returns exit code 7"

rm -f "$TEMP_CFG"


echo "--- Workspace Validation Tests ---"

# Test 7: Missing audit workspace
# Use a temporary directory so team files remain untouched.

TEST_DIR=$(mktemp -d)
MISSING_DIR="$TEST_DIR/nonexistent_audit"

bash -c '
    source "$1/sysaudit_logger.sh"
    source "$1/sysaudit_ceiling.sh"

    AUDIT_DIR="$2"
    MAX_DISK_USAGE=100
    LOG_FILE="$3"
    LOG_LEVEL=INFO

    check_disk_ceiling
' _ "$ROOT" "$MISSING_DIR" "$TEST_DIR/test.log" >/dev/null 2>&1

check_test "$?" 4 "Invalid workspace returns exit code 4"

rm -rf -- "$TEST_DIR"


echo "--- Disk Storage Validation Tests ---"

DISK_TEST_DIR=$(mktemp -d)
mkdir -p "$DISK_TEST_DIR/audit"

# Create a 2 MB test file inside the temporary audit folder
head -c 2097152 /dev/zero > "$DISK_TEST_DIR/audit/sample.audit"

# Helper to run the real disk-checking function
run_disk_test() {
    local limit="$1"

    bash -c '
        source "$1/sysaudit_logger.sh"
        source "$1/sysaudit_ceiling.sh"

        AUDIT_DIR="$2"
        MAX_DISK_USAGE="$3"
        LOG_FILE="$4"
        LOG_LEVEL=INFO

        check_disk_ceiling
    ' _ "$ROOT" "$DISK_TEST_DIR/audit" "$limit" \
        "$DISK_TEST_DIR/test.log" >/dev/null 2>&1
}

# Test 8: Disk usage below the configured limit
run_disk_test 100
check_test "$?" 0 "Disk usage below limit"

# Test 9: Disk usage exceeds the configured limit
run_disk_test 1
check_test "$?" 5 "Disk over-allocation returns exit code 5"

# Test 10: Verify warning was actually logged
if grep -q '\[WARNING\].*Disk ceiling reached' \
    "$DISK_TEST_DIR/test.log"; then
    check_test 0 0 "Disk warning recorded in log"
else
    check_test 1 0 "Disk warning recorded in log"
fi

# Test 11: Invalid disk limit
run_disk_test invalid
check_test "$?" 7 "Invalid disk limit returns exit code 7"

# Boundary test: Disk usage exactly equals the configured limit
# Use an empty temporary audit directory and a zero-MB ceiling.
BOUNDARY_DIR=$(mktemp -d)

bash -c '
    source "$1/sysaudit_logger.sh"
    source "$1/sysaudit_ceiling.sh"

    AUDIT_DIR="$2"
    MAX_DISK_USAGE=0
    LOG_FILE="$3"
    LOG_LEVEL=INFO

    check_disk_ceiling
' _ "$ROOT" "$BOUNDARY_DIR" "$DISK_TEST_DIR/boundary.log" \
    >/dev/null 2>&1

check_test "$?" 5 "Zero-MB disk ceiling triggers warning"

rm -rf -- "$BOUNDARY_DIR"

echo "--- Security Permission Tests ---"

# KNOWN DEFECT:
# The application supports --delegate, but usage.txt
# does not document this command.
# Test 12 intentionally fails until documentation is fixed.
# Do not remove this test to hide the defect.
# Test 12: Help output includes supported command options
HELP_OUTPUT=$(bash "$ROOT/sysaudit.sh" --help 2>&1)

if printf '%s\n' "$HELP_OUTPUT" | grep -q -- '--run' &&
   printf '%s\n' "$HELP_OUTPUT" | grep -q -- '--daemon' &&
   printf '%s\n' "$HELP_OUTPUT" | grep -q -- '--delegate'; then
    check_test 0 0 "Help displays required command options"
else
    check_test 1 0 "Help displays required command options"
fi

echo "--- Application Authorization Tests ---"
# Test 13: Unauthorized user cannot execute --run
if [ "$(id -un)" != "auditmanager" ]; then
    bash "$ROOT/sysaudit.sh" --run >/dev/null 2>&1
    check_test "$?" 2 "Unauthorized --run returns exit code 2"
else
    echo "SKIP: Unauthorized --run test requires a non-authorized user"
fi

# Test 14: USER environment variable cannot bypass authorization
if [ "$(id -un)" != "auditmanager" ]; then
    USER=auditmanager bash "$ROOT/sysaudit.sh" --run >/dev/null 2>&1
    check_test "$?" 2 "USER spoofing attempt is rejected"
else
    echo "SKIP: USER spoofing test requires a non-authorized user"
fi

# Test 15: Unauthorized user cannot delegate
if [ "$(id -un)" != "auditmanager" ]; then
    bash "$ROOT/sysaudit.sh" --delegate </dev/null >/dev/null 2>&1
    check_test "$?" 2 "Unauthorized --delegate returns exit code 2"
else
    echo "SKIP: Unauthorized delegation test requires a non-authorized user"
fi

echo "--- Extended Configuration Validation Tests ---"

# Run the real validator with an isolated configuration.
run_config_test() {
    local key="$1"
    local value="$2"

    bash -c '
        source "$1/validator.sh"

        SCAN_INTERVAL_SECONDS=60
        MAX_DISK_USAGE=100
        RETENTION_DAYS=14
        CLEANUP_INTERVAL_DAYS=3
        LOG_LEVEL=INFO
        DEFAULT_MODE=run

        printf -v "$2" "%s" "$3"
        validate_config
    ' _ "$ROOT" "$key" "$value" >/dev/null 2>&1
}

# Test 16: Invalid scan interval
run_config_test SCAN_INTERVAL_SECONDS abc
check_test "$?" 7 "Invalid scan interval is rejected"

# Test 17: Zero scan interval
run_config_test SCAN_INTERVAL_SECONDS 0
check_test "$?" 7 "Zero scan interval is rejected"

# Test 18: Invalid retention days
run_config_test RETENTION_DAYS -5
check_test "$?" 7 "Negative retention days are rejected"

# Test 19: Invalid cleanup interval
run_config_test CLEANUP_INTERVAL_DAYS abc
check_test "$?" 7 "Invalid cleanup interval is rejected"

# Test 20: Invalid log level
run_config_test LOG_LEVEL LOUD
check_test "$?" 7 "Invalid log level is rejected"

# Test 21: Invalid operating mode
run_config_test DEFAULT_MODE xyz
check_test "$?" 7 "Invalid operating mode is rejected"

echo "=============================="

# Test 22: Archive script rejects invalid arguments
bash "$ROOT/sysaudit_archive.sh" --invalid >/dev/null 2>&1
check_test "$?" 1 "Archive script rejects invalid arguments"

# Tests 23-25: Archive creation and preservation
echo "--- Automated Archive Creation Tests ---"

ARCHIVE_QA_ROOT=$(mktemp -d)
ARCHIVE_QA_READY=1

# Copy the required project files into an isolated workspace
if ! cp "$ROOT"/sysaudit*.sh "$ROOT/validator.sh" \
    "$ROOT/sysaudit.cfg" "$ARCHIVE_QA_ROOT/"; then
    ARCHIVE_QA_READY=0
fi

mkdir -p "$ARCHIVE_QA_ROOT/audit"

# Change configuration ONLY inside the temporary copy
sed -i \
    "s|^AUDIT_DIR=.*|AUDIT_DIR=$ARCHIVE_QA_ROOT/audit|" \
    "$ARCHIVE_QA_ROOT/sysaudit.cfg"

sed -i \
    "s|^LOG_FILE=.*|LOG_FILE=$ARCHIVE_QA_ROOT/archive-test.log|" \
    "$ARCHIVE_QA_ROOT/sysaudit.cfg"

# Create two sample reports
printf 'CPU usage: 25%%\n' > "$ARCHIVE_QA_ROOT/audit/cpu.audit"
printf 'Security status: OK\n' > "$ARCHIVE_QA_ROOT/audit/security.audit"

# Run the temporary copy
if [ "$ARCHIVE_QA_READY" -eq 1 ]; then
    bash "$ARCHIVE_QA_ROOT/sysaudit_archive.sh" --force \
        >/dev/null 2>&1
    archive_rc=$?
else
    archive_rc=1
fi

# Test 23: Archive execution succeeds
check_test "$archive_rc" 0 "Archive creation succeeds"

# Test 24: Both reports are inside the archive
if [ "$archive_rc" -eq 0 ] &&
   find "$ARCHIVE_QA_ROOT/audit" -maxdepth 1 \
       -name '*.tar.gz' -print -quit | grep -q . &&
   tar -tzf "$ARCHIVE_QA_ROOT"/audit/*.tar.gz 2>/dev/null |
       grep -qx 'cpu.audit' &&
   tar -tzf "$ARCHIVE_QA_ROOT"/audit/*.tar.gz 2>/dev/null |
       grep -qx 'security.audit'; then
    check_test 0 0 "Archive contains both audit reports"
else
    check_test 1 0 "Archive contains both audit reports"
fi

# Test 25: Originals are removed
if [ "$archive_rc" -eq 0 ] &&
   [ ! -e "$ARCHIVE_QA_ROOT/audit/cpu.audit" ] &&
   [ ! -e "$ARCHIVE_QA_ROOT/audit/security.audit" ]; then
    check_test 0 0 "Original audit reports removed after archiving"
else
    check_test 1 0 "Original audit reports removed after archiving"
fi

# Test 26: Maintenance interval prevents early execution
printf 'Interval test\n' > "$ARCHIVE_QA_ROOT/audit/interval.audit"

bash "$ARCHIVE_QA_ROOT/sysaudit_archive.sh" \
    >/dev/null 2>&1
interval_rc=$?

if [ "$interval_rc" -eq 0 ] &&
   [ -f "$ARCHIVE_QA_ROOT/audit/interval.audit" ]; then
    check_test 0 0 "Three-day maintenance interval enforced"
else
    check_test 1 0 "Three-day maintenance interval enforced"
fi

# Test 27: --force bypasses the maintenance interval
bash "$ARCHIVE_QA_ROOT/sysaudit_archive.sh" --force \
    >/dev/null 2>&1
force_rc=$?

if [ "$force_rc" -eq 0 ] &&
   [ ! -f "$ARCHIVE_QA_ROOT/audit/interval.audit" ] &&
   find "$ARCHIVE_QA_ROOT/audit" -maxdepth 1 \
       -name '*.tar.gz' -print -quit | grep -q .; then
    check_test 0 0 "Force option bypasses maintenance interval"
else
    check_test 1 0 "Force option bypasses maintenance interval"
fi

# Tests 28-29: Archive retention policy
echo "--- Archive Retention Tests ---"

# Create an expired archive and a recent archive
OLD_ARCHIVE="$ARCHIVE_QA_ROOT/audit/old_retention_test.tar.gz"
NEW_ARCHIVE="$ARCHIVE_QA_ROOT/audit/new_retention_test.tar.gz"

printf 'Expired archive\n' > "$OLD_ARCHIVE"
printf 'Recent archive\n' > "$NEW_ARCHIVE"

# Make the old archive 16 days old
touch -d '16 days ago' "$OLD_ARCHIVE"

# Run maintenance with --force to trigger retention cleanup
bash "$ARCHIVE_QA_ROOT/sysaudit_archive.sh" --force \
    >/dev/null 2>&1
retention_rc=$?

# Test 28: Expired archive is removed
if [ "$retention_rc" -eq 0 ] &&
   [ ! -e "$OLD_ARCHIVE" ]; then
    check_test 0 0 "Expired archives removed after retention period"
else
    check_test 1 0 "Expired archives removed after retention period"
fi

# Test 29: Recent archive remains
if [ "$retention_rc" -eq 0 ] &&
   [ -f "$NEW_ARCHIVE" ]; then
    check_test 0 0 "Recent archives preserved during retention cleanup"
else
    check_test 1 0 "Recent archives preserved during retention cleanup"
fi

# Clean up temporary test files
rm -rf -- "$ARCHIVE_QA_ROOT"

echo "Passed: $passed"
echo "Failed: $failed"

if [ "$failed" -gt 0 ]; then
    exit 1
fi

exit 0
