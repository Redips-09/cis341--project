#!/usr/bin/env bash
#===============================================================================
# File    : setup.sh
# Project : CIS 341 Fall 2026 - System Health Monitor & Security Auditing Daemon
# Author  : Felix Tu
# Date    : 2026-11-08
#
# What it does:
#   Sets up the whole project on a Linux machine in one step, so nobody has
#   to type the README commands by hand:
#     1. checks that the commands the scanner and archive job need exist
#     2. creates the auditmanager account
#     3. creates the audit folder and the log file (paths from sysaudit.cfg)
#     4. copies the program to the folder the systemd units point to
#     5. installs the systemd service and timer and starts them
#     6. checks that the daemon is running
#   Running it again is safe, for example after downloading a newer version:
#   the reports, archives, log and the installed sysaudit.cfg (which may hold
#   delegated users) are kept; the program files are replaced.
#
# Usage:  sudo bash setup.sh [--dry-run] [--no-service]
#         bash setup.sh --help
#
# Where things go is not hard-coded here: the install folder and the service
# user come from systemd/sysaudit.service (ExecStart= and User=), and the
# audit folder and log file come from sysaudit.cfg.
#
# Exit status: 0 setup finished (warnings may have been printed),
#              1 setup failed, the daemon did not start, or bad argument.
#
# Requires: Linux, bash 4.2+, useradd, install, systemd (unless --no-service)
#===============================================================================

SRC="$(cd "$(dirname "$0")" && pwd)"      # the downloaded project folder
UNIT_DIR=/etc/systemd/system               # local unit files go here (book p.45, p.116)
PROGRAMS="sysaudit.sh sysaudit_archive.sh sysaudit_ceiling.sh sysaudit_logger.sh sysaudit_scanner.sh sysaudit_summary.sh validator.sh"
UNITS="sysaudit.service sysaudit-maintenance.service sysaudit-maintenance.timer"
DRY_RUN=0
NO_SERVICE=0
STATUS=0

show_usage() {
    cat <<'EOF'
Usage: sudo bash setup.sh [--dry-run] [--no-service]

Installs the sysaudit monitor: creates the auditmanager account, the audit
folder and the log file, copies the program to its install folder, and
installs and starts the systemd service and nightly timer.
Safe to run again: data, the log and the installed sysaudit.cfg are kept.

Options:
  --dry-run      show every step without changing anything (no root needed)
  --no-service   set everything up but do not install or start systemd units
  -h, --help     show this message

Exit status: 0 setup finished (warnings may have been printed),
             1 setup failed, the daemon did not start, or bad argument.
EOF
}

say()  { echo "[setup] $*"; }
warn() { echo "[setup] WARNING: $*" >&2; }
die()  { echo "[setup] ERROR: $*" >&2; exit 1; }

# run COMMAND...   run one step, or only print it with --dry-run.
# Previewing first is the book's advice before doing anything that changes
# the system (p.201). A failed step stops the setup (exit 1, p.187).
run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "        would run: $*"
        return 0
    fi
    "$@" || die "this step failed: $*"
}

#--- options ----------------------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)    DRY_RUN=1 ;;
        --no-service) NO_SERVICE=1 ;;
        -h|--help)    show_usage; exit 0 ;;
        *)            echo "[setup] ERROR: unknown option '$1'" >&2
                      show_usage >&2
                      exit 1 ;;
    esac
    shift
done

#--- 0. checks before anything is changed -----------------------------------------

if [ "$DRY_RUN" -eq 0 ]; then
    [ "$(uname -s)" = "Linux" ] || die "this setup only works on Linux (try --dry-run to preview)"
    [ "$(id -u)" -eq 0 ] || die "run it as root: sudo bash $0"
else
    say "dry run: nothing will be changed"
fi

for f in $PROGRAMS usage.txt sysaudit.cfg; do
    [ -f "$SRC/$f" ] || die "missing $f; run setup.sh from inside the project folder"
done
for u in $UNITS; do
    [ -f "$SRC/systemd/$u" ] || die "missing systemd/$u"
done

# Windows line endings break bash ("$'\r': command not found").
# tr -cd keeps only the carriage-return bytes, so wc -c counts them.
crlf=""
for f in "$SRC"/*.sh "$SRC/sysaudit.cfg" "$SRC"/systemd/*; do
    [ "$(tr -cd '\r' < "$f" | wc -c)" -eq 0 ] || crlf="$crlf $(basename "$f")"
done
if [ -n "$crlf" ]; then
    die "Windows (CRLF) line endings in:$crlf. Re-download the zip, or fix them with: sed -i 's/\r\$//' *.sh sysaudit.cfg systemd/*"
fi

# Install folder and service user, read from the unit file so they always match.
INSTALL_DIR=$(sed -n 's|^ExecStart=\(.*\)/sysaudit\.sh.*|\1|p' "$SRC/systemd/sysaudit.service")
SERVICE_USER=$(sed -n 's|^User=||p' "$SRC/systemd/sysaudit.service")
if [ -z "$INSTALL_DIR" ] || [ -z "$SERVICE_USER" ]; then
    die "could not read ExecStart= and User= from systemd/sysaudit.service"
fi
grep -q "^ExecStart=$INSTALL_DIR/sysaudit_archive.sh" "$SRC/systemd/sysaudit-maintenance.service" \
    || die "systemd/sysaudit-maintenance.service does not start $INSTALL_DIR/sysaudit_archive.sh"

# A sysaudit.cfg that is already installed is kept, because --delegate may
# have added users to it. The paths are read from the config that will be used.
if [ -f "$INSTALL_DIR/sysaudit.cfg" ]; then
    CFG="$INSTALL_DIR/sysaudit.cfg"
    KEEP_CFG=1
else
    CFG="$SRC/sysaudit.cfg"
    KEEP_CFG=0
fi
source "$SRC/sysaudit_logger.sh"           # the team's config reader (load_config)
load_config "$CFG" || die "$CFG has a bad line (load_config returned $?)"
for key in AUDIT_DIR LOG_FILE; do
    case "${!key}" in
        /*) ;;
        *)  die "$key in $CFG must be an absolute path, not '${!key}'" ;;
    esac
done

say "project folder : $SRC"
say "install folder : $INSTALL_DIR (from systemd/sysaudit.service)"
say "service user   : $SERVICE_USER"
say "audit folder   : $AUDIT_DIR (from $CFG)"
say "log file       : $LOG_FILE"

#--- 1. commands the scanner and archive job need -----------------------------------

missing=""
for c in hostname uptime free df ss ps who last tar find du stat; do
    command -v "$c" > /dev/null 2>&1 || missing="$missing $c"
done
if [ -z "$missing" ]; then
    say "1/6 all needed commands are installed"
else
    warn "1/6 missing commands:$missing. Scans will fail until the packages that provide them are installed (on Ubuntu, procps and iproute2 provide free, uptime, ps and ss)."
fi

#--- 2. the service account (useradd, book p.261) -----------------------------------

if id "$SERVICE_USER" > /dev/null 2>&1; then
    say "2/6 user $SERVICE_USER already exists"
else
    say "2/6 creating user $SERVICE_USER"
    run useradd -r -m -s /bin/bash "$SERVICE_USER"
fi
# The account's own group (useradd normally makes one with the same name).
SERVICE_GROUP=$(id -gn "$SERVICE_USER" 2> /dev/null) || SERVICE_GROUP="$SERVICE_USER"

#--- 3. audit folder and log file ---------------------------------------------------
# install -d creates the folder (and its parents) or just fixes the owner and
# mode of an existing one; it never deletes what is inside.

say "3/6 audit folder $AUDIT_DIR"
run install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 755 "$AUDIT_DIR"

if [ -f "$LOG_FILE" ]; then
    say "3/6 log file exists, keeping its contents: $LOG_FILE"
    run chown "$SERVICE_USER:$SERVICE_GROUP" "$LOG_FILE"
    run chmod 664 "$LOG_FILE"
else
    say "3/6 creating log file $LOG_FILE"
    run install -D -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 664 /dev/null "$LOG_FILE"
fi

#--- 4. copy the program --------------------------------------------------------------
# Owned by the service user, because --delegate rewrites sysaudit.cfg in place.
# Scripts 755 and text files 644 (chmod octal values, book p.136).

say "4/6 copying the program to $INSTALL_DIR"
run install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 755 "$INSTALL_DIR"
for f in $PROGRAMS; do
    run install -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 755 "$SRC/$f" "$INSTALL_DIR/$f"
done
run install -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 644 "$SRC/usage.txt" "$INSTALL_DIR/usage.txt"

if [ "$KEEP_CFG" -eq 1 ]; then
    say "4/6 keeping the installed $INSTALL_DIR/sysaudit.cfg (the new default is $SRC/sysaudit.cfg)"
else
    run install -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 644 "$SRC/sysaudit.cfg" "$INSTALL_DIR/sysaudit.cfg"
fi

#--- 5. systemd service and timer (book p.45, pp.49-54, p.116) ------------------------

if [ "$NO_SERVICE" -eq 1 ]; then
    say "5/6 skipping systemd (--no-service)"
elif [ "$DRY_RUN" -eq 0 ] && ! command -v systemctl > /dev/null 2>&1; then
    warn "5/6 systemctl not found: the service and timer were not installed (run the monitor by hand)"
    NO_SERVICE=1
else
    say "5/6 installing and starting the service and timer"
    for u in $UNITS; do
        run install -o root -g root -m 644 "$SRC/systemd/$u" "$UNIT_DIR/$u"
    done
    run systemctl daemon-reload                       # re-read the unit files (p.54)
    run systemctl enable sysaudit.service sysaudit-maintenance.timer
    run systemctl restart sysaudit.service            # restart also loads new code on a re-run
    run systemctl restart sysaudit-maintenance.timer
fi

#--- 6. check the result ----------------------------------------------------------------

if [ "$DRY_RUN" -eq 1 ]; then
    say "6/6 dry run finished; nothing was changed"
    exit 0
fi

if [ "$NO_SERVICE" -eq 0 ]; then
    sleep 2                                           # give the first scan loop time to start
    if systemctl is-active --quiet sysaudit.service; then
        say "6/6 sysaudit.service is running"
    else
        warn "6/6 sysaudit.service is not running; see: journalctl -u sysaudit.service -n 20"
        STATUS=1
    fi
    if systemctl is-active --quiet sysaudit-maintenance.timer; then
        say "6/6 sysaudit-maintenance.timer is active (archive job every night at midnight)"
    else
        warn "6/6 sysaudit-maintenance.timer is not active; see: systemctl status sysaudit-maintenance.timer"
    fi
    echo "--- last lines of $LOG_FILE"
    tail -n 5 "$LOG_FILE"
fi

echo
echo "Setup finished. Useful commands:"
echo "  follow the log      : tail -f $LOG_FILE"
echo "  one scan by hand    : sudo -u $SERVICE_USER $INSTALL_DIR/sysaudit.sh --run"
echo "  archive job now     : sudo -u $SERVICE_USER $INSTALL_DIR/sysaudit_archive.sh --force"
echo "  delegate a user     : sudo -u $SERVICE_USER $INSTALL_DIR/sysaudit.sh --delegate"
if [ "$NO_SERVICE" -eq 0 ]; then
    echo "  daemon status       : systemctl status sysaudit.service"
    echo "  after editing $INSTALL_DIR/sysaudit.cfg: sudo systemctl restart sysaudit.service"
fi
exit "$STATUS"
