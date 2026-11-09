# CIS 341 — Linux System Health Monitor & Security Auditing Daemon (`sysaudit`)

A modular Linux system health monitor, security auditing daemon, and automated maintenance engine implemented in Bash for the CIS 341 course project.

## 1. Project Architecture & File Breakdown

* `sysaudit.sh`: Main executable controller. Dispatches execution modes (`--run`, `--daemon`, `--delegate`, `--help`), validates execution identity against `auditmanager`, invokes configuration validators, and manages the daemon loop.
* `sysaudit.cfg`: Externalized key-value configuration file decoupling all paths, thresholds, and operational intervals.
* `sysaudit_scanner.sh`: Inspects host hardware, process tables, socket listeners, and login records, generating `scan_<TIMESTAMP>.audit` reports.
* `sysaudit_logger.sh`: Self-monitoring logging engine with timestamped entries, severity ranking (`[INFO]`, `[WARN]`, `[ERROR]`), STDERR mirroring, and file-dump size tracking.
* `sysaudit_ceiling.sh`: Workspace storage envelope monitor. Measures total directory footprint using `du -sb` and triggers high-priority warning interrupts if `MAX_DISK_USAGE` is exceeded.
* `sysaudit_archive.sh`: Scheduled maintenance utility. Bundles raw `*.audit` text reports into compressed `.tar.gz` archives, verifies archive integrity before unlinking source files, enforces 14-day circular pruning, and logs archive metadata.
* `sysaudit_summary.sh`: Inspects archive repositories using `stat -c` to extract archive counts, largest archive names, exact byte sizes, and timestamps.
* `validator.sh`: Schema verification module ensuring integer boundaries and allowed string values for all configuration parameters.
* `usage.txt`: Interactive usage statement and exit code dictionary.
* `systemd/`: Contains unit files for continuous daemon execution (`sysaudit.service`) and scheduled nightly maintenance (`sysaudit-maintenance.service`, `sysaudit-maintenance.timer`).
* `tests/`: Automated unit and integration test suites (`test_tasks_5_7_8.sh` and `test_person_e.sh`) verifying all exit codes, log integrity, and security sandboxing.

## 2. Environment Setup (Linux VM / Ubuntu )

Run the following commands in your shell to configure permissions, dependencies, dedicated user accounts, and system paths:

```bash
# 1. Create the dedicated auditmanager service account
sudo useradd -r -m -s /bin/bash auditmanager 2>/dev/null || true
sudo mkdir -p /home/auditmanager
sudo chown -R auditmanager:auditmanager /home/auditmanager
sudo chmod o+rx "$HOME" "$(dirname "$PWD")" "$PWD"

# 2. Initialize the audit workspace and self-monitoring log
sudo install -d -o auditmanager -g auditmanager -m 755 /course_project/audit
sudo install -o auditmanager -g auditmanager -m 664 /dev/null /var/log/sysaudit_daemon.log
```

---

## 3. How to Run the Project

### Interactive USAGE Engine
```bash
./sysaudit.sh --help
# Or run with no arguments to immediately trigger the usage screen:
./sysaudit.sh
```

### Single Audit Scan Cycle
```bash
sudo -u auditmanager ./sysaudit.sh --run
```

### Continuous Daemon Loop
```bash
sudo -u auditmanager ./sysaudit.sh --daemon
```

### Scheduled Maintenance & Archiving
```bash
# Run maintenance immediately by bypassing the 3-day elapsed rule:
sudo -u auditmanager ./sysaudit_archive.sh --force
```

### Delegate Execution Authority
```bash
sudo -u auditmanager ./sysaudit.sh --delegate
```

## 4. Systemd Boot & Nightly Timer Setup

To configure the daemon to launch on boot and schedule the archive engine to run every night at midnight:

```bash
# 1. Deploy project scripts to production directory
sudo mkdir -p /opt/sysaudit
sudo cp -r ./* /opt/sysaudit/
sudo chmod +x /opt/sysaudit/*.sh
sudo chown -R auditmanager:auditmanager /opt/sysaudit

# 2. Install systemd service and timer unit files
sudo cp systemd/sysaudit.service /etc/systemd/system/
sudo cp systemd/sysaudit-maintenance.service /etc/systemd/system/
sudo cp systemd/sysaudit-maintenance.timer /etc/systemd/system/

# 3. Reload systemd, enable, and start services
sudo systemctl daemon-reload
sudo systemctl enable --now sysaudit.service
sudo systemctl enable --now sysaudit-maintenance.timer
```
