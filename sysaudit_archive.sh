#!/bin/bash

## File		:sysaudit_archive.sh
##Project	:CIS341 Fall 2026
##Task		:archive old *.audit reports, then prune old archives. 
##Author		:Parvinder Singh
##Date		:2026-10-31
##
##run by sysaudit-archive.timer avery night at midnight.
##the script will decide if the work is due: it only run when CLEAN_INTERVAL_DAYS 
##have passed.
##
##uasage: sysaudit_archive.sh [-f| --force]

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/sysaudit.cfg"
RC=0
 
## ---------- the one option: --force skips the 3-day rule ----------
 
FORCE=0
case "$1" in
	-f|--force)
		FORCE=1
		;;
	"")
		;;
	*)
		echo "sysaudit_archive: unknown argument '$1'" 1>&2
		exit 1
		;;
esac
 
## ---------- load the team's code, the config and the log ----------
 
for part in sysaudit_logger.sh sysaudit_summary.sh sysaudit_ceiling.sh; do
	if [ ! -f "$SCRIPT_DIR/$part" ]; then                  # -f = regular file, book p.206
		echo "sysaudit_archive: required file $part not found" 1>&2
		exit 1
	fi
	source "$SCRIPT_DIR/$part"
done
 
load_config "$CONFIG_FILE" || exit $?     # reads sysaudit.cfg: 3 = missing, 7 = bad line
init_log || exit $?                       # 3 = no LOG_FILE, 6 = cannot write the log
 
## logs the error (log_exception also prints it to STDERR) and ends the script.

die(){     # die CODE "message"
	log_exception "$1" "$2"
	exit "$1"
}
 
## ---------- check the settings ----------
 
require_setting(){     # require_setting NAME VALUE     
	if [ -z "$2" ]; then                                # (-z = empty, book p.205)
		die 7 "setting $1 is missing or empty in sysaudit.cfg"
	fi
}
 
require_setting AUDIT_DIR "$AUDIT_DIR"
require_setting ARCHIVE_EXTENSIONS "$ARCHIVE_EXTENSIONS"
require_setting ARCHIVE_PREFIX "$ARCHIVE_PREFIX"
require_setting LAST_RUN_FILENAME "$LAST_RUN_FILENAME"
 
## -ge only works on whole numbers, so text like "abc" or an empty value fails

if [ ! "$CLEANUP_INTERVAL_DAYS" -ge 1 ] 2>/dev/null; then
	die 7 "CLEANUP_INTERVAL_DAYS must be a whole number, 1 or more"
fi
if [ ! "$RETENTION_DAYS" -ge 1 ] 2>/dev/null; then
	die 7 "RETENTION_DAYS must be a whole number, 1 or more"
fi
 
## go into the workspace so file names are short. cd fails if it is not a folder.
cd "$AUDIT_DIR" || die 4 "workspace is missing or not a folder: $AUDIT_DIR"
 
log_msg INFO "Archive job started (every $CLEANUP_INTERVAL_DAYS days, keep archives $RETENTION_DAYS days, force=$FORCE)"
 
## ---------- is the job due? (the "every 3 days" rule) ----------
 
today_n=$(( `date +%s` / 86400 ))
last=0
if [ -f "$LAST_RUN_FILENAME" ]; then
	read last < "$LAST_RUN_FILENAME"       # the day number saved by the last good run (book p.202)
fi
if [ -z "$last" ]; then
	last=0
fi
since=$(( today_n - last ))
 
if [ "$FORCE" -eq 0 ] && [ "$since" -lt "$CLEANUP_INTERVAL_DAYS" ]; then     # && in an if, book p.205
	log_msg INFO "Not due yet: last run was $since day(s) ago, need $CLEANUP_INTERVAL_DAYS"
	exit 0
fi
 
## ---------- task 3: archive every *.audit file, then delete the originals ----------
## ls | wc -l counts the files (book p.209). tar czf packs them; the originals are
## only deleted if tar succeeded.
 
count=`ls *.audit 2>/dev/null | wc -l`
if [ "$count" -eq 0 ]; then
	log_msg INFO "No .audit files to archive"
else
	ARCHIVE_NAME="${ARCHIVE_PREFIX}_`date +%Y%m%d_%H%M%S`.tar.gz"
	if tar czf "$ARCHIVE_NAME" *.audit; then
		log_msg INFO "Archive created: $ARCHIVE_NAME ($count files)"
		if rm -f *.audit; then                     # rm -f, book p.112
			log_msg INFO "Deleted the $count original .audit files"
		else
			log_msg WARN "Could not delete some original .audit files"
			RC=8
		fi
	else
		rm -f "$ARCHIVE_NAME"                      # throw away the broken archive
		die 8 "tar failed, the original files were kept"
	fi
fi
 
## ---------- task 6: delete archives older than RETENTION_DAYS ----------
## find -mtime +N lists files older than N days, the same test as the book's
## cleanup job (p.112, p.118). "+14" means 15 or more FULL days old.
## sed turns "tar.gz,zip" into "tar.gz zip" (book p.200) and for loop goes through them.
 
for ext in $(echo "$ARCHIVE_EXTENSIONS" | sed 's/,/ /g'); do
	old=$(find . -name "*.$ext" -mtime +"$RETENTION_DAYS")
	for f in $old; do
		if rm -f "$f"; then
			log_msg INFO "Pruned old archive: $f"
		else
			log_msg WARN "Could not delete old archive: $f"
			RC=9
		fi
	done
done
 
## ---------- finish ----------
## remember this run only if everything worked, so a failed night is tried again
 
if [ "$RC" -eq 0 ]; then
	echo "$today_n" > "$LAST_RUN_FILENAME"
	log_msg INFO "Last-run day saved: $today_n"
fi
 
check_disk_ceiling          # teammate B, task 8: warns in the log if AUDIT_DIR is too big
archive_summary             # teammate B, task 7: writes the archive summary line
 
log_msg INFO "Archive job finished (exit code $RC)"
exit "$RC"
