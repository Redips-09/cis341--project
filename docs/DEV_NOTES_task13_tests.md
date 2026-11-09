# Development Note: Task 13, Functionality Verification Suite

**Scripts:** `tests/test_task13_validation.sh`, `tests/run_all_tests.sh` · **Code under test:** `sysaudit.sh`, `sysaudit_archive.sh`, `validator.sh`, `sysaudit_logger.sh`, `sysaudit_ceiling.sh`, `sysaudit_summary.sh` · **Author:** Felix Tu · **Date:** 2026-11-08

Textbook: Nemeth et al., *UNIX and Linux System Administration Handbook*, 5th edition (2018). Page numbers below are the printed page numbers. In the PDF copy, add 47 (for example, p. 958 is PDF page 1005).

## What the task asks for

A structured set of tests that runs automatically and simulates:
- standard boundary configurations, missing files, corrupted target paths and malformed configurations;
- over-allocation storage limits, to confirm the warning flag is triggered;
- unprivileged account validation hacks, to confirm the sandboxing barriers hold.

## What was there before

Two suites were already in `main`:
- **`test_tasks_5_7_8.sh`** (mine, 28 tests): missing config (3), bad config line (7), log file that can't be written (6), missing audit folder (4), and the disk warning (5, `[WARNING]` in the log and on STDERR).
- **`test_person_e.sh`** (Satvik, 30 tests, merged in PR #6): the help screen, missing and malformed config, missing audit folder, the disk warning, a 0 MB ceiling, a wrong user refused for `--run` and `--delegate`, a `USER=auditmanager` spoofing attempt, six bad values for `validate_config`, and the archive job (tasks 3 and 6).

Between them every item in the task list had at least one test. What was still missing:
- **Real boundary values.** The only edge test uses a 0 MB ceiling. `validate_config` rejects 0 before the disk check ever runs, and on Linux an empty folder is already 4096 bytes, so that test is over the limit, not exactly at it.
- **Missing files other than the config**, and **corrupted paths other than "the folder does not exist"**.
- **Bypass attempts other than `USER` spoofing.**
- **A single command to run every suite.**

The new suite adds what was missing. A few checks overlap with Satvik's on purpose: four bad config values and the wrong-user refusals for `--run` and `--delegate`. Satvik's suite runs these against the repo's real `sysaudit.cfg`. Mine runs them on a sandbox copy with its own config, so they still work if someone uses `--delegate` on the VM and changes the real file.

## How I built it

1. **Three kinds of tests.** The book lists the tests a project should run (p. 958). Three of them fit a shell project:
   - *Static code analysis:* `bash -n` on every script. This checks the syntax without running anything (p. 188).
   - *Unit tests:* load the team's functions with `source`, call one function with a chosen input, and compare the result with the expected one. This is the same idea as the book's `TestOrdinal` example (p. 967).
   - *Integration tests:* run the real programs `sysaudit.sh` and `sysaudit_archive.sh` "in its intended execution environment" (p. 958), with their real arguments.
2. **A sandbox, so tests never touch anything real.** Every test starts with `fresh`, which sets up the following inside a `mktemp` folder:
   - a copy of the programs,
   - an empty audit folder,
   - a `sysaudit.cfg` written by the test.

   `sysaudit.sh` reads `sysaudit.cfg` from its own folder, so the copy reads the test config. This means the `--delegate` test (which edits the config with `sed -i`) can never change the team's real file, and no test needs root, `/var/log` or `/course_project/audit`. Every test also starts from a clean state. The book says "Ideally, tests should have no cross-dependencies" (p. 959).
3. **Checking exit codes and STDERR.** Most checks compare `$?` (p. 204) with the code listed in `usage.txt`, using `-eq` (Table 7.3, p. 205). The helpers `check`, `ok` and `skip_test` take their values as `$1`, `$2`, `$3` (p. 203). STDOUT and STDERR are saved to separate files, so a test can check that an error message really goes to STDERR (Christiansen's rules, p. 188). Log lines are checked with `grep` (p. 197).
4. **Boundary values.** The footnote on p. 967 says a full set of unit tests exercises every path through the code. `check_disk_ceiling` uses `-ge`, so its two paths meet exactly at the limit. The test builds a folder that is 1 byte under 1 MB, then exactly 1 MB. `du` counts the folder itself as well as the files (p. 108), so the test measures the folder with an empty file inside first and adds the remaining bytes. Every number key is also tried with 0, a negative number and text, and once with the smallest legal values (all 1). Command-line values (`--interval 0`, `--max-disk 0`) go through the same checks.
5. **Missing files, corrupted paths, malformed config.**
   - *Missing:* no `sysaudit.cfg` (3), a missing module for the archive job (1), a log folder that doesn't exist yet (it gets created), no `.audit` files, and no last-run file.
   - *Corrupted paths:*
     - `AUDIT_DIR` is a regular file. This is tested through every function and both programs; all return 4.
     - `--audit-dir` points to a folder that doesn't exist (4).
     - The log path is inside a regular file (6).
     - The audit folder is read-only (`chmod 500`), or has no search bit (`chmod 600`). The directory bits are explained on p. 133 and the octal values in Table 5.3, p. 136.
     - `AUDIT_DIR` is a broken symbolic link.
     - The folder name contains spaces. The book says scripts "must be prepared to deal with spaces in filenames" (p. 202).
   - *Malformed config:*
     - spaces around `=`, which the book says to leave out (p. 192),
     - a lower-case key, a key starting with a digit, or a key with a hyphen,
     - a key with no `=`,
     - an empty file,
     - Windows CRLF line endings,
     - values like `$(command)`, which must be rejected and never run.
6. **Over-allocation.** Besides the function test, the warning is checked through the real archive job. The test fills the folder with `/dev/urandom` data, because zeros compress to almost nothing and the folder would drop under the limit after archiving. It also checks four things:
   - the job still finishes after the warning;
   - a run under the limit logs `[INFO]` and no `[WARNING]`;
   - `--max-disk 1` overrides the config value (task 9);
   - the daemon keeps looping after a warning. `timeout` returns 124 when it has to stop a command that is still running, which is the result we want.
7. **Playing the unprivileged user without extra accounts.** Instead of creating users with `useradd`, which needs root, the sandbox config lists only `auditmanager` in `AUTHORIZED_USERS`. The person running the tests is not `auditmanager`, so they are the unprivileged user. Access is decided by the effective user (p. 67), and `id -un` prints the effective user name. The tests check that:
   - `--run`, `--daemon` and `--delegate` are refused with code 2;
   - the refusal is printed on STDERR;
   - nothing is written before the refusal;
   - command-line overrides don't get around the check;
   - names that look like yours (`ADMINx`, `xADMIN`, `ADMIN_2`, `admin`, `ADM` when the tester is `ADMIN`) don't let you in;
   - a user who *is* in the list gets through.
8. **Bypass attempts (the "hacks").** Satvik's suite already tries `USER=auditmanager`. These four are the other ways in:
   1. Set `AUTHORIZED_USERS` to your own name in the environment.
   2. The same, but with no `AUTHORIZED_USERS` line in the config.
   3. Put a fake `id` command earlier in `PATH` that prints `auditmanager`. This is exactly what the book warns about for `su`: an arbitrary program with the right name "sneaked into your search path" (p. 70). In my first review I suggested this fake `id` as a way to *test* the auditmanager path. It turned out to get around the check, so it became a bypass test instead.
   4. Skip `sysaudit.sh` and run `sysaudit_archive.sh` directly.
9. **SKIP instead of a fake PASS.** Some tests can't run everywhere:
   - `chmod` has no effect for root or on Windows;
   - Git Bash can't make real symbolic links;
   - `--run` needs the scanner's Linux commands (`free`, `ss`, `uptime`, `last`).

   Those tests print `SKIP` with the reason and are never counted as passed. Failures are never hidden either. The book says "Avoid the temptation to ignore or overlook broken tests" (p. 959).
10. **One command for everything.** `run_all_tests.sh` runs every `tests/test_*.sh` with a `for` loop (p. 207) and prints the result of each suite. It exits with 1 if any suite failed, which follows the book's advice to make failed tests hard to ignore (p. 959). A new `test_*.sh` file is picked up automatically.

## How it runs

```bash
bash tests/run_all_tests.sh            # every suite
bash tests/test_task13_validation.sh   # only task 13
```

Output from a run on 2026-11-08 (shortened):

```
=== CIS 341 - Task 13 Verification Suite (running as ADMIN) ===
--- Static check: bash -n on every script (p.188) ---
PASS  every script passes bash -n
--- 1. Boundary configurations ---
PASS  1 byte under the 1 MB ceiling returns 0
PASS  exactly at the 1 MB ceiling returns 5
PASS  validate_config rejects 'MAX_DISK_USAGE=0'
...
--- 1. Corrupted target paths ---
PASS  AUDIT_DIR is a regular file: sysaudit.sh --run returns 4
SKIP  permission tests (chmod has no effect here: root user or not a Linux file system)
...
--- 2. Over-allocation storage limit ---
PASS  archive job over the limit writes [WARNING] to the log
PASS  the daemon keeps scanning after a [WARNING] (4 warnings in 5 seconds)
--- 3. Sandboxing: unprivileged account and bypass attempts ---
PASS  user 'ADMIN' is refused by sysaudit.sh --run
PASS  AUTHORIZED_USERS="ADMINx" does not let 'ADMIN' in
FAIL  bypass: a fake 'id' in PATH does not fool the user check (expected 2, got 1)
FAIL  bypass: user 'ADMIN' is also refused by sysaudit_archive.sh (expected 2, got 0)
-----------------------------
Passed: 66   Failed: 4   Skipped: 3
```

Exit status: `test_task13_validation.sh` returns the number of failed tests (0 = all passed). `run_all_tests.sh` returns 0 if every suite passed, 1 if any failed.

## What the tests found

Four tests fail on the current code. These are problems in the program, not in the tests. To check that, I applied the fixes below to a scratch copy of the repo: all 70 tests passed there, and the other two suites still passed. **None of these fixes are in the repo yet.** The owners should decide on them.

| Failing test | Problem | Suggested fix |
|---|---|---|
| `--delegate` refusal reported on STDERR | `delegate_user` prints `Unauthorized Access` to STDOUT. | Add `>&2` to that `echo` (p. 188). |
| Config without `AUTHORIZED_USERS` + the variable in the environment | If the config has no `AUTHORIZED_USERS` line, `usercheck` uses whatever value is in the environment. | `unset AUTHORIZED_USERS` before `load_config` in `sysaudit.sh`, or add `AUTHORIZED_USERS` to the required keys in `validate_config`. |
| Fake `id` in `PATH` | `usercheck` and `delegate_user` run whichever `id` comes first in the caller's `PATH`. | Set `PATH=/usr/local/bin:/usr/bin:/bin` at the top of `sysaudit.sh`, or call `/usr/bin/id` by its full path. This is the book's advice for `su` (p. 70). |
| `sysaudit_archive.sh` refuses a wrong user | The archive job has no user check at all. | Run the same `AUTHORIZED_USERS` check after `load_config` and exit with 2. |

The first three are in the task 11/12 code in `sysaudit.sh` (Ryan). The last one is in `sysaudit_archive.sh` (Parvinder).

How serious they are: if `/course_project/audit` and `sysaudit.cfg` belong to `auditmanager` with tight permissions, the real files are still protected by the file permissions. What these hacks get around is the program's own user check, which task 11 requires.

## Textbook pages used

| What I used | Page |
|---|---|
| Kinds of tests: static code analysis, unit tests, integration tests | 958 |
| Code coverage alone is misleading; test the complex code | 958 (footnote 1) |
| Tests should not depend on each other; don't ignore broken tests; make failures hard to ignore | 959 |
| Unit test: known input, compare with the expected output | 966 to 967 |
| A full set of unit tests exercises every path through the code (boundary tests) | 967 (footnote 3) |
| Comment block at the top of the script; `bash -n` syntax check | 188 |
| Error messages go to STDERR and the program exits non-zero | 188 |
| Usage message on bad arguments, validate inputs, meaningful exit codes | 187 |
| `$?` holds the exit status; functions that exit with a specific code | 204 |
| `$1`, `$2`, `$#` in functions | 203 |
| `&&` and `\|\|` | 192 |
| No spaces around `=` | 192 |
| Scripts must handle spaces in filenames | 202 |
| `-eq`, `-ne`, `-ge`, `-z` comparisons | 205 (Table 7.3) |
| `-d`, `-e`, `-f`, `-w` file tests | 206 (Table 7.4) |
| `for` loops; `$((...))` arithmetic | 207, 209 |
| `grep` and its `-c` and `-v` options; `head` | 196 to 197 |
| `cut -f` to pick a field | 194 |
| `du` adds up the sizes in a directory | 108 |
| Directory permission bits (search bit, write + execute) | 133 |
| `chmod` octal values | 136 (Table 5.3) |
| Real and effective UIDs; the effective one decides access | 67 |
| A fake program sneaked into the search path; type full paths | 70 |
| `sudo -u` to run a command as another user | 72 |
| `useradd` to create an account | 261 |

Not from the book:
- `mktemp`, the `trap ... EXIT` cleanup, `timeout` and its exit code 124, and `cmp`;
- `head -c` with `/dev/zero` and `/dev/urandom` to make test files of an exact size;
- `${ME,,}` and `${ME^^}` (lower and upper case), and `[ -L ]` for symbolic links;
- the `<<<` here-string, and `sed -i 's/$/\r/'` to make CRLF line endings.

## Checking on the Linux VM

Run the suite there as a normal user (not root and not `auditmanager`), so the three skipped tests run too.

For the task 14 presentation, the same barrier can also be shown with a real second account:

```bash
sudo useradd -m intruder                      # p. 261
sudo -u intruder /opt/sysaudit/sysaudit.sh --run; echo "exit code $?"    # p. 72, expect 2
```

## Testing

Run on 2026-11-08 under Windows 11 with Git Bash (bash 5.2):
- **`test_task13_validation.sh`:** 66 passed, 4 failed, 3 skipped. The 4 failures are the four problems listed above. The 3 skips are the `chmod` tests, the symbolic link test and the `--max-disk` scanner test, which this system can't do.
- **`test_tasks_5_7_8.sh`:** 28 of 28 passed.
- **`test_person_e.sh`** (Satvik's, after PR #6): 30 of 30 passed.

Not yet run on Linux.
