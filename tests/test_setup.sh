#!/usr/bin/env bash
#===============================================================================
# File    : tests/test_setup.sh
# Project : CIS 341 Fall 2026 - sysaudit
# Author  : Felix Tu
# Date    : 2026-11-08
#
# Tests setup.sh without installing anything. Every test uses --dry-run on a
# sandbox copy of the project whose systemd units point into a temporary
# folder, so no root, no systemd and no real /opt, /var/log or
# /course_project are needed. The one test without --dry-run is only run by a
# normal user, where setup.sh must refuse before changing anything.
#
# Usage (from the repo folder): bash tests/test_setup.sh
# Exit status = number of failed tests (0 = all passed).
#===============================================================================

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)" || { echo "test_setup: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
P="$T/project"                 # sandbox copy of the downloaded project
OUT="$T/stdout.txt"
ERR="$T/stderr.txt"
pass=0
fail=0

check() {   # check ACTUAL EXPECTED "description"
    if [ "$1" -eq "$2" ]; then
        echo "PASS  $3"; pass=$((pass + 1))
    else
        echo "FAIL  $3 (expected $2, got $1)"; fail=$((fail + 1))
    fi
}
ok() {      # ok STATUS "description"
    if [ "$1" -eq 0 ]; then
        echo "PASS  $2"; pass=$((pass + 1))
    else
        echo "FAIL  $2"; fail=$((fail + 1))
    fi
}

# A fresh sandbox project. Its units start the program from $T/opt/sysaudit
# and its config uses $T/audit and $T/log/sysaudit_daemon.log.
fresh() {
    rm -rf "$P" "$T/opt" "$T/audit" "$T/log"
    mkdir -p "$P/systemd"
    cp "$ROOT"/*.sh "$ROOT/usage.txt" "$ROOT/sysaudit.cfg" "$P"/
    cp "$ROOT"/systemd/* "$P/systemd"/
    sed -i "s|/opt/sysaudit|$T/opt/sysaudit|" "$P"/systemd/*.service
    sed -i "s|^AUDIT_DIR=.*|AUDIT_DIR=$T/audit|; s|^LOG_FILE=.*|LOG_FILE=$T/log/sysaudit_daemon.log|" "$P/sysaudit.cfg"
}

setup_run() { bash "$P/setup.sh" "$@" > "$OUT" 2> "$ERR" < /dev/null; }

echo "=== CIS 341 - setup.sh tests ==="

fresh
setup_run --help; check $? 0 "--help returns 0"
grep -q '^Usage: sudo bash setup.sh' "$OUT"; ok $? "--help prints the usage line"

fresh
setup_run --bogus; check $? 1 "an unknown option returns 1"
grep -q "unknown option '--bogus'" "$ERR"; ok $? "the unknown option is named on STDERR"

if [ "$(id -u)" -ne 0 ]; then
    fresh
    setup_run; check $? 1 "without --dry-run, a normal user is refused (or not Linux)"
    grep -q 'ERROR' "$ERR" && [ ! -e "$T/opt" ] && [ ! -e "$T/audit" ]
    ok $? "the refusal is on STDERR and nothing was created"
else
    echo "SKIP  refusal test (running as root would really install)"
fi

fresh
setup_run --dry-run; check $? 0 "--dry-run returns 0"
grep -q 'nothing was changed' "$OUT" && [ ! -e "$T/opt" ] && [ ! -e "$T/audit" ] && [ ! -e "$T/log" ]
ok $? "--dry-run creates nothing"
grep -q "install folder : $T/opt/sysaudit (from systemd/sysaudit.service)" "$OUT"
ok $? "the install folder is read from ExecStart= in the unit file"
grep -q "service user   : auditmanager" "$OUT"
ok $? "the service user is read from User= in the unit file"
grep -q "would run: install -d .* $T/audit\$" "$OUT" && grep -q "would run: install -D .* /dev/null $T/log/sysaudit_daemon.log" "$OUT"
ok $? "the audit folder and log file come from sysaudit.cfg"
grep -q 'would run: systemctl enable sysaudit.service sysaudit-maintenance.timer' "$OUT"
ok $? "the service and timer are enabled"

fresh
setup_run --dry-run --no-service
! grep -q 'would run: systemctl' "$OUT"; ok $? "--no-service skips every systemctl step"

# Second run: an installed config and an existing log must be kept.
fresh
mkdir -p "$T/opt/sysaudit" "$T/log"
sed "s|^AUTHORIZED_USERS=.*|AUTHORIZED_USERS=\"auditmanager alice\"|" "$P/sysaudit.cfg" > "$T/opt/sysaudit/sysaudit.cfg"
echo "old log line" > "$T/log/sysaudit_daemon.log"
setup_run --dry-run; check $? 0 "a second run returns 0"
grep -q 'keeping the installed' "$OUT" && ! grep -q "would run: install .*sysaudit.cfg $T/opt/sysaudit/sysaudit.cfg" "$OUT"
ok $? "a second run keeps the installed sysaudit.cfg (delegated users)"
grep -q 'keeping its contents' "$OUT" && ! grep -q 'would run: install -D .* /dev/null' "$OUT"
ok $? "a second run keeps the existing log file"

# Problems that must stop the setup before anything is changed.
fresh
sed -i "s|^ExecStart=.*|ExecStart=/somewhere/else/sysaudit_archive.sh|" "$P/systemd/sysaudit-maintenance.service"
setup_run --dry-run; check $? 1 "the two services pointing to different folders returns 1"

fresh
sed -i 's/$/\r/' "$P/sysaudit_logger.sh"
setup_run --dry-run; check $? 1 "a file with Windows (CRLF) line endings returns 1"
grep -q 'CRLF.*sysaudit_logger.sh' "$ERR"; ok $? "the CRLF file is named on STDERR"

fresh
sed -i 's|^AUDIT_DIR=.*|AUDIT_DIR=relative/audit|' "$P/sysaudit.cfg"
setup_run --dry-run; check $? 1 "a relative AUDIT_DIR in sysaudit.cfg returns 1"

fresh
rm -f "$P/validator.sh"
setup_run --dry-run; check $? 1 "a missing program file returns 1"
grep -q 'missing validator.sh' "$ERR"; ok $? "the missing file is named on STDERR"

echo "-----------------------------"
echo "Passed: $pass   Failed: $fail"
exit "$fail"
