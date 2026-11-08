# Development Note: Task 5, Self-Monitoring Log

**Script:** `sysaudit_logger.sh` · **Config keys:** `LOG_FILE`, `LOG_LEVEL` · **Author:** Felix Tu · **Date:** 2026-10-30

Textbook: Nemeth et al., *UNIX and Linux System Administration Handbook*, 5th edition (2018). Page numbers below are the printed page numbers. In the PDF copy, add 47 (for example, p. 206 is PDF page 253).

## What the task asks for

The daemon needs its own log file (`/var/log/sysaudit_daemon.log`). It has to record:
- every scan loop start,
- every saved data file,
- every change to the sleep interval,
- every handled error.

Each line needs a level (`[INFO]`, `[WARN]`, `[ERROR]`) and a timestamp.

## How I built it

1. **Line format.** I started from what the book says a log line contains: a time stamp, the severity, the process name and PID, and the message (p. 294, p. 303). My lines look like this:
   `2026-10-30 10:10:52 [INFO] sysaudit[13474]: Scan loop #1 started`
2. **`log_msg` function.** It builds that line with `date '+%Y-%m-%d %H:%M:%S'` (the same `date +` style the book uses on p. 183 and p. 207) and appends it to the log with `>>` (p. 190).
3. **Log levels.** I copied the idea of the `logMsg()` function on p. 206. A `case` statement turns each level into a number (ERROR=0, WARN=1, INFO=2, DEBUG=3), and messages less important than `LOG_LEVEL` are skipped. `[WARNING]` is task 8's high-priority flag, so it is never skipped, even at `LOG_LEVEL=ERROR`.
4. **Errors to STDERR.** `[ERROR]` and `[WARNING]` lines are also printed to STDERR, because the book says error messages should go to STDERR (p. 188).
5. **One small function per event.** I added `log_scan_start`, `log_file_dump`, `log_sleep_change` and `log_exception`, so everyone on the team logs these events the same way. `log_file_dump` gets the file size with `wc -c` (p. 196).
6. **Setup and config.**
   - `init_log` creates the log file and checks that it can be written (`-w`, Table 7.4, p. 206). If not, it returns code 6.
   - `load_config` reads `sysaudit.cfg` line by line with `while read` (p. 208). The file is a list of `KEY=VALUE` assignments with no spaces around `=` (p. 192, p. 199). Our team's config has comments after the values (`MAX_DISK_USAGE=100 #disk usage ...`), so `load_config` cuts off everything after `#` and trims the spaces. The config still works with `source` too, if the task 4 owner prefers that.
7. **Testing.** I checked the syntax with `bash -n` (p. 188) and then wrote the test script.

## How it runs

The main script loads the file with `source`. After that, any part of the program can call the log functions. Output from a test run:

```
2026-10-30 10:10:52 [INFO] sysaudit[13474]: Log started (user ADMIN)
2026-10-30 10:10:52 [INFO] sysaudit[13474]: Scan loop #1 started
2026-10-30 10:10:52 [INFO] sysaudit[13474]: Saved data file /course_project/audit/audit_2026-10-23.zip (5000 bytes)
2026-10-30 10:10:52 [INFO] sysaudit[13474]: Sleep interval changed from 60 to 30 seconds
2026-10-30 10:10:52 [ERROR] sysaudit[13474]: Exception with exit code 4: example error
```

Return codes: `0` ok · `3` config file or `LOG_FILE` missing · `6` log file not writable · `7` bad line in the config.
Codes 6 and 7 are new and should be added to the exit code list in `usage.txt`.

## Textbook pages used

| What I used | Page |
|---|---|
| Comment block at the top of every script (what it does, name, date) | 188 |
| Error messages go to STDERR and the script exits with a non-zero code | 188 |
| `>>` appends to a file; `>&2` / `1>&2` sends output to STDERR | 190 to 191, 204 |
| Variables, no spaces around `=`, ALL CAPS for config values | 192 to 193 |
| A config file written as a list of variable assignments | 199 |
| `case` statement and the `logMsg()` log-level example | 206 |
| File tests `-f`, `-w` | 206 (Table 7.4) |
| `while read` loop | 208 |
| `wc -c` to count bytes | 196 |
| `date +%Y-%m-%d...` timestamps | 183, 207 |
| What a log line contains; syslog line format | 294, 303 |
| Severity levels (err, warning, info, debug) | 309 (Table 10.3) |
| Logs normally live in `/var/log` | 296 |

Not from the book: `declare -g` to create the config variables, `${value%%#*}` to cut off comments, and the `[[ =~ ]]` check of the key name (the book covers regular expressions on pp. 209 to 211, but not this bash operator).

## How to add it to the main script

In `sysaudit.sh`, after `CONFIG_FILE` is set:

```bash
source "$SCRIPT_DIR/sysaudit_logger.sh"
load_config "$CONFIG_FILE" || exit $?
init_log || exit $?

log_scan_start "$loop_number"
log_file_dump "$report_file"
log_sleep_change "$old_interval" "$SCAN_INTERVAL_SECONDS"
log_exception 4 "audit folder is missing"
```

`auditmanager` cannot write to `/var/log` by default, so the log file has to be created for that user once:

```bash
sudo install -o auditmanager -g auditmanager -m 640 /dev/null /var/log/sysaudit_daemon.log
```

## Testing

`bash tests/test_tasks_5_7_8.sh` runs 13 tests for task 5:
- the log is created and lines have a timestamp and level;
- all four required events are logged;
- `[ERROR]` also appears on STDERR;
- DEBUG lines are skipped;
- the error codes for a missing config (3), a bad config line (7) and an unwritable log (6);
- the team's real `sysaudit.cfg` loads correctly with `load_config` and with `source`.

All passed on 2026-10-30.
