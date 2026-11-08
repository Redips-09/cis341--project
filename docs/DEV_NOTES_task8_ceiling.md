# Development Note: Task 8, Disk Ceiling Warning

**Script:** `sysaudit_ceiling.sh` · **Config keys:** `AUDIT_DIR`, `MAX_DISK_USAGE` · **Author:** Felix Tu · **Date:** 2026-10-30

Textbook: Nemeth et al., *UNIX and Linux System Administration Handbook*, 5th edition (2018). Page numbers below are the printed page numbers. In the PDF copy, add 47.

## What the task asks for

Check how much space everything in the audit folder uses. If it reaches the limit (for example 100MB), write a high-priority `[WARNING]` line to the log. The limit must be set in `sysaudit.cfg`.

## How I built it

1. **Choosing `du`.** The book explains that `du` adds up the sizes of all files in a directory, while `df` reports a whole filesystem (p. 108). The task is about one folder, so I used `du`. `-s` gives one total and `-b` gives the size in bytes. `cut -f1` (p. 194) keeps just the number.
2. **The limit.** It comes from the team's existing key `MAX_DISK_USAGE=100` (in MB). The book explains that "mega" can mean 1,000,000 or 1,048,576 (p. 13). I chose 1 MB = 1024 × 1024 bytes, which matches what `du` and `ls -h` use.
3. **Checking the config value.** A `case` pattern (p. 206) rejects anything that isn't a whole number. The function then logs an `[ERROR]` and returns 7.
4. **The comparison.** I used `-ge` (greater than or equal, Table 7.3, p. 205), so exactly reaching the limit also counts. If the limit is reached, the function writes `[WARNING]`, which also goes to STDERR, and returns 5 (`DISK_CEILING_REACHED` in `usage.txt`). Otherwise it writes an `[INFO]` line.
5. **The idea behind it.** This is the basic monitoring pattern from chapter 28: measure a value, compare it to a threshold, raise an alert if it is out of range (p. 1042). `du` is one of the standard monitoring commands in Table 28.2 (p. 1057).

## How it runs

It is called on every scan loop. Output from a test run (first with a 100 MB limit, then 1 MB):

```
2026-10-30 10:10:52 [INFO] sysaudit[13474]: Disk usage OK: /course_project/audit uses 2115392 of 104857600 bytes (100 MB)
2026-10-30 10:10:52 [WARNING] sysaudit[13474]: Disk ceiling reached: /course_project/audit uses 2115392 bytes, limit is 1048576 bytes (1 MB)
```

Return codes: `0` ok · `1` du failed · `4` audit folder missing · `5` ceiling reached · `7` limit is not a number.

## Textbook pages used

| What I used | Page |
|---|---|
| Comment block at the top of the script | 188 |
| `du` adds up file sizes in a directory; `df` vs `du` | 108 |
| `du -sh ... \| sort -h` example of measuring folders | 195 |
| `cut -f` to pick a field | 194 |
| `-ge` greater-or-equal comparison | 205 (Table 7.3) |
| `case` patterns | 206 |
| `-d` file test | 206 (Table 7.4) |
| `$((...))` arithmetic | 209 |
| What MB means (powers of 2 vs 10) | 13 |
| Compare a metric with a threshold and alert | 1042 |
| `du` / `df` as monitoring commands | 1057 (Table 28.2) |

Not from the book: the `-b` option of GNU `du`.

## How to add it to the main script

```bash
source "$SCRIPT_DIR/sysaudit_logger.sh"      # must come first
source "$SCRIPT_DIR/sysaudit_ceiling.sh"

# in every scan loop:
check_disk_ceiling
# return code 5 = warning already logged, the daemon keeps running
```

For task 9 (command-line arguments override the config), set `MAX_DISK_USAGE` from the command-line option **after** `load_config`, so the command-line value wins.

## Testing

`bash tests/test_tasks_5_7_8.sh` runs 8 tests for task 8:
- 2 MB under a 100 MB limit returns 0 and logs `[INFO]`;
- 2 MB over a 1 MB limit returns 5 and logs `[WARNING]` to the log and to STDERR;
- the `[WARNING]` is still logged when `LOG_LEVEL=ERROR`;
- a non-number limit returns 7;
- a missing folder returns 4.

All passed on 2026-10-30.
