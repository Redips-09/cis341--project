#!/usr/bin/env bash
#===============================================================================
# File    : tests/test_task13_validation.sh
# Project : CIS 341 Fall 2026 - sysaudit
# Task    : #13 Comprehensive Functionality Verification Suites
# Author  : Felix Tu
# Date    : 2026-11-08
#
# What it does:
#   Runs the three groups of checks task 13 asks for:
#     1. boundary configurations, missing files, corrupted target paths and
#        malformed configurations
#     2. over-allocation of the audit folder (the [WARNING] flag from task 8)
#     3. unprivileged-account "hacks" against the user check (tasks 11, 12)
#   It starts with a bash -n syntax check of every script.
#
#   There are two kinds of tests (book p.958):
#     unit tests         load the team's functions with "source" and call them
#     integration tests  run a copy of the real programs (sysaudit.sh and
#                        sysaudit_archive.sh) from a sandbox folder
#
#   Everything happens in a temporary folder made with mktemp. The sandbox has
#   its own sysaudit.cfg, so the team's real config, /var/log and
#   /course_project/audit are never touched. No root, sudo or extra Linux
#   accounts are needed: the person running the tests plays the unprivileged
#   user by leaving their own name out of AUTHORIZED_USERS.
#
# Usage (from the repo folder):  bash tests/test_task13_validation.sh
#        or every suite at once: bash tests/run_all_tests.sh
# Exit status = number of failed tests (0 = all passed).
#
# Requires: bash 4 or newer, GNU coreutils (du -b, timeout, head, cmp), tar,
#           find. Some tests are skipped (SKIP) where the system cannot do
#           them, for example chmod tests when running as root.
#===============================================================================

ROOT="$(cd "$(dirname "$0")/.." && pwd)"        # the repo folder
TEST_DIR="$(mktemp -d)" || { echo "test_task13: mktemp failed" >&2; exit 1; }
APP="$TEST_DIR/app"                     # sandbox copy of the programs
WS="$TEST_DIR/audit"                    # audit workspace (AUDIT_DIR)
LOG="$TEST_DIR/sysaudit_daemon.log"     # daemon log (LOG_FILE)
OUT="$TEST_DIR/stdout.txt"
ERR="$TEST_DIR/stderr.txt"
LIMIT=20                                # seconds before a hanging test is stopped
ME="$(id -un)"                          # the user running the tests
pass=0
fail=0
skip=0

# A name that is NOT the person running the tests. Normally auditmanager; if
# the tests are run as auditmanager, a made-up name is used instead.
if [ "$ME" = "auditmanager" ]; then
    OTHER="sysaudit_other"
else
    OTHER="auditmanager"
fi

# Remove the temporary folder however the script ends. chmod first, because
# the permission tests leave folders that cannot be deleted otherwise.
cleanup() {
    chmod -R u+rwx "$TEST_DIR" 2>/dev/null
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

if ! command -v timeout > /dev/null 2>&1; then
    echo "test_task13: the timeout command (GNU coreutils) is required" >&2
    exit 1
fi

#--- result helpers -------------------------------------------------------------

# check ACTUAL EXPECTED "description"   compare two exit codes (-eq, p.205)
check() {
    if [ "$1" -eq "$2" ]; then
        echo "PASS  $3"
        pass=$((pass + 1))
    else
        echo "FAIL  $3 (expected $2, got $1)"
        fail=$((fail + 1))
    fi
}

# ok STATUS "description"   STATUS is $? of a test command; 0 means true
ok() {
    if [ "$1" -eq 0 ]; then
        echo "PASS  $2"
        pass=$((pass + 1))
    else
        echo "FAIL  $2"
        fail=$((fail + 1))
    fi
}

skip_test() {
    echo "SKIP  $1"
    skip=$((skip + 1))
}

#--- sandbox helpers ------------------------------------------------------------

# write_cfg [LINE ...]   write the sandbox sysaudit.cfg. Extra lines go at the
# end; load_config reads from top to bottom, so they win.
write_cfg() {
    {
        echo "AUDIT_DIR=$WS"
        echo "LOG_FILE=$LOG"
        echo "SCAN_INTERVAL_SECONDS=60"
        echo "MAX_DISK_USAGE=100"
        echo "RETENTION_DAYS=14"
        echo "CLEANUP_INTERVAL_DAYS=3"
        echo "DEFAULT_MODE=run"
        echo "LOG_LEVEL=INFO"
        echo "ARCHIVE_EXTENSIONS=tar.gz,zip"
        echo "ARCHIVE_PREFIX=audit_archive"
        echo "LAST_RUN_FILENAME=.last_archive_run"
        echo "AUTHORIZED_USERS=\"$ME\""
        for line in "$@"; do echo "$line"; done
    } > "$APP/sysaudit.cfg"
}

# Config where only $OTHER may run the program (for the group 3 tests).
deny_cfg() {
    write_cfg "AUTHORIZED_USERS=\"$OTHER\"" "$@"
}

# drop_key KEY   delete every KEY=... line from the sandbox config
drop_key() {
    grep -v "^$1=" "$APP/sysaudit.cfg" > "$TEST_DIR/cfg.tmp"
    mv "$TEST_DIR/cfg.tmp" "$APP/sysaudit.cfg"
}

# Start every test from a clean sandbox: a fresh copy of the programs, an
# empty audit folder, no log, and the default config (which allows $ME).
fresh() {
    chmod -R u+rwx "$TEST_DIR" 2>/dev/null
    rm -rf "$APP" "$WS" "$LOG" "$OUT" "$ERR" "$TEST_DIR/marker" \
           "$TEST_DIR/not_a_dir" "$TEST_DIR/a_file" "$TEST_DIR/dangling" \
           "$TEST_DIR/new" "$TEST_DIR/fakebin" "$TEST_DIR/elsewhere.log" \
           "$SPACE_WS"
    mkdir -p "$APP" "$WS"
    cp "$ROOT"/*.sh "$ROOT/usage.txt" "$APP"/
    write_cfg
}

# unit COMMAND [ARGS]   unit test: load the team's functions and the sandbox
# config in a subshell, then run one function. STDOUT -> $OUT, STDERR -> $ERR.
unit() {
    (
        source "$ROOT/sysaudit_logger.sh"
        source "$ROOT/validator.sh"
        source "$ROOT/sysaudit_summary.sh"
        source "$ROOT/sysaudit_ceiling.sh"
        load_config "$APP/sysaudit.cfg" || exit $?
        "$@"
    ) > "$OUT" 2> "$ERR"
}

# Integration tests: run the sandbox copy of a program. STDIN is empty so a
# prompt can never wait for input, and timeout stops anything that hangs.
main_prog() {
    timeout "$LIMIT" bash "$APP/sysaudit.sh" "$@" > "$OUT" 2> "$ERR" < /dev/null
}
archive_job() {
    timeout "$LIMIT" bash "$APP/sysaudit_archive.sh" "$@" > "$OUT" 2> "$ERR" < /dev/null
}

#--- what this system can test ----------------------------------------------------

# chmod has no effect for root, or on Windows file systems (Git Bash).
mkdir "$TEST_DIR/probe"
chmod 500 "$TEST_DIR/probe"
if [ -w "$TEST_DIR/probe" ]; then PERMS_WORK=no; else PERMS_WORK=yes; fi
chmod 700 "$TEST_DIR/probe"
rmdir "$TEST_DIR/probe"

# Windows (Git Bash) usually copies the file instead of making a symlink.
ln -s "$TEST_DIR/nowhere" "$TEST_DIR/probe_link" 2>/dev/null
if [ -L "$TEST_DIR/probe_link" ]; then LINKS_WORK=yes; else LINKS_WORK=no; fi
rm -f "$TEST_DIR/probe_link"

# sysaudit.sh --run stops early if the scanner's commands are missing.
SCANNER_OK=yes
for c in hostname uptime free df ss ps who last; do
    command -v "$c" > /dev/null 2>&1 || SCANNER_OK=no
done

SPACE_WS="$TEST_DIR/audit folder with spaces"

echo "=== CIS 341 - Task 13 Verification Suite (running as $ME) ==="

#===============================================================================
echo "--- Static check: bash -n on every script (p.188) ---"
bad=""
for f in "$ROOT"/*.sh "$ROOT"/tests/*.sh; do
    bash -n "$f" 2> /dev/null || bad="$bad $(basename "$f")"
done
[ -z "$bad" ]; ok $? "every script passes bash -n${bad:+ (failed:$bad)}"

#===============================================================================
echo "--- 1. Boundary configurations ---"

# check_disk_ceiling uses -ge, so exactly reaching the limit must warn and one
# byte less must not. du also counts the folder itself (on some file systems
# its size grows with each file in it), so measure the folder with an empty
# file already inside, then fill that file up to exactly 1 MB (1048576 bytes).
fresh; write_cfg "MAX_DISK_USAGE=1"
: > "$WS/fill.audit"
base=$(du -sb "$WS" | cut -f1)
head -c $((1048576 - base - 1)) /dev/zero > "$WS/fill.audit"
used=$(du -sb "$WS" | cut -f1)
if [ "$used" -eq 1048575 ]; then
    unit check_disk_ceiling; check $? 0 "1 byte under the 1 MB ceiling returns 0"
    head -c $((1048576 - base)) /dev/zero > "$WS/fill.audit"
    unit check_disk_ceiling; check $? 5 "exactly at the 1 MB ceiling returns 5"
else
    skip_test "ceiling boundary (du reports $used bytes, could not build an exact 1 MB folder)"
fi

# validate_config (validator.sh) must reject every out-of-range value with 7.
for line in "MAX_DISK_USAGE=0" "SCAN_INTERVAL_SECONDS=0" "SCAN_INTERVAL_SECONDS=-5" \
            "RETENTION_DAYS=0" "CLEANUP_INTERVAL_DAYS=abc" "LOG_LEVEL=VERBOSE" \
            "DEFAULT_MODE=sometimes" "MAX_DISK_USAGE="; do
    fresh; write_cfg "$line"
    unit validate_config; check $? 7 "validate_config rejects '$line'"
done

fresh; write_cfg "MAX_DISK_USAGE=1" "SCAN_INTERVAL_SECONDS=1" "RETENTION_DAYS=1" "CLEANUP_INTERVAL_DAYS=1"
unit validate_config; check $? 0 "validate_config accepts the smallest legal values (all 1)"

fresh; write_cfg "MAX_DISK_USAGE=1"           # the default file already has MAX_DISK_USAGE=100
value=$( source "$ROOT/sysaudit_logger.sh"; load_config "$APP/sysaudit.cfg" && echo "$MAX_DISK_USAGE" )
[ "$value" = "1" ]; ok $? "a key written twice uses the last value"

# Command-line values go through the same checks as the config (task 9).
fresh; main_prog --run --interval 0;  check $? 7 "sysaudit.sh --run --interval 0 returns 7"
fresh; main_prog --run --max-disk 0;  check $? 7 "sysaudit.sh --run --max-disk 0 returns 7"
fresh; main_prog --run --interval;    check $? 1 "an override with no value returns 1"

#===============================================================================
echo "--- 1. Missing files ---"

fresh; rm -f "$APP/sysaudit.cfg"
main_prog --run; check $? 3 "sysaudit.sh --run with no sysaudit.cfg returns 3"
grep -q "sysaudit.cfg' not found" "$ERR"; ok $? "the missing config is reported on STDERR"

fresh; rm -f "$APP/sysaudit.cfg"
archive_job --force; check $? 3 "sysaudit_archive.sh with no sysaudit.cfg returns 3"

fresh; write_cfg "LOG_FILE=$TEST_DIR/new/folder/sysaudit.log"
unit init_log; code=$?
[ "$code" -eq 0 ] && [ -f "$TEST_DIR/new/folder/sysaudit.log" ]
ok $? "a log folder that does not exist yet is created"

fresh; rm -f "$APP/sysaudit_summary.sh"
archive_job --force; check $? 1 "archive job with a missing module (sysaudit_summary.sh) returns 1"
grep -q "sysaudit_summary.sh not found" "$ERR"; ok $? "the missing module is named on STDERR"

fresh
archive_job --force; check $? 0 "archive job with no .audit files returns 0"
grep -q 'No .audit files to archive' "$LOG"; ok $? "an empty workspace is logged, not treated as an error"

fresh
archive_job; code=$?          # no --force and no .last_archive_run file yet
[ "$code" -eq 0 ] && ! grep -q 'Not due yet' "$LOG" && [ -f "$WS/.last_archive_run" ]
ok $? "no last-run file: the job runs and creates .last_archive_run"

#===============================================================================
echo "--- 1. Corrupted target paths ---"

fresh; echo "I am a file" > "$TEST_DIR/not_a_dir"; write_cfg "AUDIT_DIR=$TEST_DIR/not_a_dir"
unit validate_config;    check $? 4 "AUDIT_DIR is a regular file: validate_config returns 4"
unit check_disk_ceiling; check $? 4 "AUDIT_DIR is a regular file: check_disk_ceiling returns 4"
unit archive_summary;    check $? 4 "AUDIT_DIR is a regular file: archive_summary returns 4"
main_prog --run;         check $? 4 "AUDIT_DIR is a regular file: sysaudit.sh --run returns 4"
archive_job --force;     check $? 4 "AUDIT_DIR is a regular file: sysaudit_archive.sh returns 4"

fresh; main_prog --run --audit-dir "$TEST_DIR/missing"
check $? 4 "--audit-dir pointing to a missing folder returns 4"

fresh; touch "$TEST_DIR/a_file"
main_prog --run --log-file "$TEST_DIR/a_file/log.txt"
check $? 6 "--log-file inside a regular file returns 6"

# Directory bits (p.133): w+x are needed to create files, x to enter at all.
if [ "$PERMS_WORK" = yes ]; then
    fresh; chmod 500 "$WS"                         # r-x
    unit validate_config; check $? 4 "audit folder without write permission returns 4"
    main_prog --run;      check $? 4 "sysaudit.sh --run with a read-only audit folder returns 4"
    chmod 600 "$WS"                                # rw-, no search bit
    unit validate_config; check $? 4 "audit folder without the search (x) bit returns 4"
    chmod 700 "$WS"
else
    skip_test "permission tests (chmod has no effect here: root user or not a Linux file system)"
fi

if [ "$LINKS_WORK" = yes ]; then
    fresh; ln -s "$TEST_DIR/deleted_folder" "$TEST_DIR/dangling"
    write_cfg "AUDIT_DIR=$TEST_DIR/dangling"
    unit validate_config; check $? 4 "AUDIT_DIR is a broken symbolic link: returns 4"
else
    skip_test "broken symbolic link test (this system cannot make real symlinks)"
fi

# Scripts must cope with spaces in path names (p.202).
fresh; mkdir -p "$SPACE_WS"; write_cfg "AUDIT_DIR=$SPACE_WS"
echo "report" > "$SPACE_WS/scan_1.audit"
unit validate_config;    check $? 0 "AUDIT_DIR with spaces passes validate_config"
unit check_disk_ceiling; check $? 0 "AUDIT_DIR with spaces: check_disk_ceiling returns 0"
archive_job --force; code=$?
n_archives=$(ls "$SPACE_WS"/*.tar.gz 2> /dev/null | wc -l)
[ "$code" -eq 0 ] && [ "$n_archives" -eq 1 ] && [ ! -f "$SPACE_WS/scan_1.audit" ]
ok $? "AUDIT_DIR with spaces: archive job packs and removes the .audit file"

#===============================================================================
echo "--- 1. Malformed configurations ---"

# Lines must be KEY=VALUE with an upper-case key and no spaces around = (p.192).
for line in "MAX_DISK_USAGE = 100" "max_disk_usage=100" "1ST_KEY=value" "MAX-DISK=100"; do
    fresh; write_cfg "$line"
    unit true; check $? 7 "load_config rejects the line '$line'"
done

fresh; write_cfg "THIS LINE IS WRONG"
main_prog --run; check $? 7 "sysaudit.sh --run with a malformed line returns 7"
grep -q 'bad line in .*THIS LINE IS WRONG' "$ERR"; ok $? "the bad line is shown on STDERR"

fresh; : > "$APP/sysaudit.cfg"
unit validate_config; check $? 7 "an empty sysaudit.cfg is rejected by validate_config"

fresh; write_cfg "MAX_DISK_USAGE"              # no "=" at all
unit validate_config; check $? 7 "a key with no '=' (so no value) is rejected"

fresh; sed -i 's/$/\r/' "$APP/sysaudit.cfg"     # Windows line endings
unit validate_config; check $? 7 "a config saved with Windows (CRLF) line endings is rejected"

# The values must be stored as text. If load_config ever ran them, the
# marker file would appear.
fresh; write_cfg "MAX_DISK_USAGE=\$(touch $TEST_DIR/marker)" "LOG_LEVEL=\`touch $TEST_DIR/marker\`"
main_prog --run; code=$?
[ "$code" -eq 7 ] && [ ! -e "$TEST_DIR/marker" ]
ok $? "config values like \$(command) are rejected and never run"

#===============================================================================
echo "--- 2. Over-allocation storage limit ---"

fresh; write_cfg "MAX_DISK_USAGE=1"
head -c 2097152 /dev/zero > "$WS/big.audit"                  # 2 MB
unit check_disk_ceiling; check $? 5 "2 MB in a workspace with a 1 MB ceiling returns 5"
grep -Eq '\[WARNING\] .*Disk ceiling reached: .* uses [0-9]+ bytes, limit is 1048576 bytes \(1 MB\)' "$LOG"
ok $? "the [WARNING] line shows the bytes used and the limit"

# Through the real maintenance job. Random data does not compress, so the
# folder is still over 1 MB after the .audit file is archived.
fresh; write_cfg "MAX_DISK_USAGE=1"
head -c 2097152 /dev/urandom > "$WS/scan_big.audit"
archive_job --force
grep -q '\[WARNING\] .*Disk ceiling reached' "$LOG"; ok $? "archive job over the limit writes [WARNING] to the log"
grep -q 'Disk ceiling reached' "$ERR";             ok $? "archive job over the limit prints the warning on STDERR"
grep -q 'Archive job finished' "$LOG";             ok $? "the archive job still finishes after the warning"

fresh                                                      # config: 100 MB
head -c 2097152 /dev/urandom > "$WS/scan_big.audit"
archive_job --force
grep -q '\[INFO\] .*Disk usage OK' "$LOG" && ! grep -q '\[WARNING\]' "$LOG"
ok $? "archive job under the limit logs [INFO] and no [WARNING]"

if [ "$SCANNER_OK" = yes ]; then
    fresh                                                  # config: 100 MB
    head -c 2097152 /dev/zero > "$WS/big.audit"
    main_prog --run --max-disk 1
    if grep -q 'Failed to create or complete audit report' "$LOG"; then
        skip_test "--max-disk override test (the scanner failed on this system, see generate_audit)"
    else
        grep -q '\[WARNING\] .*limit is 1048576 bytes (1 MB)' "$LOG"
        ok $? "--max-disk 1 overrides MAX_DISK_USAGE=100 and triggers the warning"
    fi
else
    skip_test "--max-disk override test (scanner commands such as free, ss or last are missing; run on Linux)"
fi

# The warning must not stop the daemon. timeout returns 124 when it has to
# stop a command that is still running, which is what we want here.
fresh; write_cfg "MAX_DISK_USAGE=1"
head -c 2097152 /dev/zero > "$WS/big.audit"
timeout 5 bash "$APP/sysaudit.sh" --daemon --interval 1 > "$OUT" 2> "$ERR" < /dev/null; code=$?
warnings=$(grep -c '\[WARNING\] .*Disk ceiling reached' "$LOG" 2> /dev/null)
[ "$code" -eq 124 ] && [ "${warnings:-0}" -ge 2 ]
ok $? "the daemon keeps scanning after a [WARNING] (${warnings:-0} warnings in 5 seconds)"

#===============================================================================
echo "--- 3. Sandboxing: unprivileged account and bypass attempts ---"
# In this group only $OTHER is allowed, so $ME plays the unprivileged user.

fresh; deny_cfg
main_prog --run; check $? 2 "user '$ME' is refused by sysaudit.sh --run"
grep -q "Unable to verify: $ME" "$ERR"; ok $? "the refusal is reported on STDERR"
[ ! -e "$LOG" ] && [ -z "$(ls -A "$WS")" ]; ok $? "nothing is written before the refusal (no log, no report)"

fresh; deny_cfg
main_prog --daemon --interval 1; check $? 2 "user '$ME' is refused by sysaudit.sh --daemon"

fresh; deny_cfg
main_prog --run --audit-dir "$TEST_DIR/elsewhere" --log-file "$TEST_DIR/elsewhere.log"; code=$?
[ "$code" -eq 2 ] && [ ! -e "$TEST_DIR/elsewhere.log" ]
ok $? "command-line overrides do not get around the user check"

# Exact match only: names that look like $ME must not let $ME in.
lookalikes="${ME}x x${ME} ${ME}_2"
if [ "${ME,,}" != "$ME" ]; then
    lookalikes="$lookalikes ${ME,,}"
else
    lookalikes="$lookalikes ${ME^^}"
fi
if [ "${#ME}" -gt 3 ]; then
    lookalikes="$lookalikes ${ME:0:3}"
fi
for name in $lookalikes; do
    fresh; write_cfg "AUTHORIZED_USERS=\"$name\""
    main_prog --run; check $? 2 "AUTHORIZED_USERS=\"$name\" does not let '$ME' in"
done

fresh                                   # the default config allows $ME
main_prog --run; code=$?
[ "$code" -ne 2 ] && grep -q "Verified user: $ME" "$OUT"
ok $? "a user listed in AUTHORIZED_USERS gets past the check"

if [ "$ME" = "auditmanager" ]; then
    skip_test "--delegate refusal (you are auditmanager; run the suite as another user)"
else
    fresh; cp "$APP/sysaudit.cfg" "$TEST_DIR/cfg.before"
    timeout "$LIMIT" bash "$APP/sysaudit.sh" --delegate > "$OUT" 2> "$ERR" <<< "$ME"
    check $? 2 "user '$ME' cannot use --delegate"
    cmp -s "$APP/sysaudit.cfg" "$TEST_DIR/cfg.before" && [ ! -e "$APP/sysaudit.cfg.bak" ]
    ok $? "a refused --delegate leaves sysaudit.cfg unchanged"
    grep -q 'Unauthorized' "$ERR"; ok $? "the --delegate refusal is reported on STDERR (p.188)"
fi

# Bypass 1: put your own name in AUTHORIZED_USERS in the environment.
# load_config runs after the environment is read, so the config must win.
fresh; deny_cfg
( export AUTHORIZED_USERS="$ME"; main_prog --run )
check $? 2 "bypass: AUTHORIZED_USERS=$ME in the environment is ignored"

# Bypass 2: the same, when the config has no AUTHORIZED_USERS line.
fresh; deny_cfg; drop_key AUTHORIZED_USERS
( export AUTHORIZED_USERS="$ME"; main_prog --run )
check $? 2 "bypass: config without AUTHORIZED_USERS + the variable in the environment is refused"

# Bypass 3: a fake "id" command earlier in PATH that prints an allowed name.
# The book warns about this trick for su (p.70): a program with the right name
# sneaked into the search path.
fresh; deny_cfg
mkdir -p "$TEST_DIR/fakebin"
real_id="$(command -v id)"
cat > "$TEST_DIR/fakebin/id" <<EOF
#!/bin/sh
# fake id: lies about the user name, passes everything else to the real id
if [ "\$1" = "-un" ]; then echo "$OTHER"; exit 0; fi
exec "$real_id" "\$@"
EOF
chmod +x "$TEST_DIR/fakebin/id"
( PATH="$TEST_DIR/fakebin:$PATH"; main_prog --run )
check $? 2 "bypass: a fake 'id' in PATH does not fool the user check"

# Bypass 4: skip sysaudit.sh and run the maintenance job directly.
fresh; deny_cfg
echo "report" > "$WS/scan_1.audit"
archive_job --force
check $? 2 "bypass: user '$ME' is also refused by sysaudit_archive.sh"

#===============================================================================
echo "-----------------------------"
echo "Passed: $pass   Failed: $fail   Skipped: $skip"
exit "$fail"
