# durable.sh — Signal-36 Hardened Shell Primitives

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Shell: bash](https://img.shields.io/badge/shell-bash%204.0%2B-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform: Linux](https://img.shields.io/badge/platform-Linux-green.svg)](https://www.kernel.org/)

> **One-line install:** `source /path/to/durable.sh`  
> **Protects against:** Android `traced_perf` (signal 36), mid-write kills, stale git locks, silent failures

---

## The Problem

On Android (and some Linux kernels), **short-lived processes are killed at ~10–15% rate** by `traced_perf` sending **signal 36** (`BIONIC_SIGNAL_PROFILER`, `SIGRTMIN+2`). This breaks:

| Symptom | Root Cause |
|---------|------------|
| `git` exits 164 ("Real-time signal 2") | Signal 36 default = terminate |
| `python3 -c 'print(1)'` dies randomly | Same |
| `rpm` scriptlet dies mid-transaction | Same |
| File written but truncated (21 bytes) | Kill mid-`>` redirect |
| Retry loop in `$(...)` subshell dies too | Subshell inherits signal |
| `git push` fails but script exits 0 | `tail` masks exit code |
| Stale `.git/index.lock` wedges repo | Killed `git add` leaves lock |

**This is not a "freeze" — it's a targeted kill of short-lived processes.**  
Measured: `sleep 0.001` → 0/40 kills; `sleep 0.2` → 6/40 (15%); `sleep 3.0` → 12%.  
**Risk plateaus at ~15% — making processes longer buys nothing.**

---

## The Solution: Three Patterns

### 1. `trap '' 36` — Inherited Immunity
```bash
trap '' 36  # One line, parent shell, protects ALL descendants forever
```
- `SIG_IGN` is **inherited across fork+exec**
- **Cannot be reset by children** (unlike handlers)
- Proven: 10/240 kills → 1/240 with this guard

### 2. Atomic Writes — `tmp → mv`
```bash
# Instead of: cmd > file
cmd | durable::atomic_write file
# Or: durable::atomic_write_str file "content"
```
- Temp file on same filesystem + `mv` = atomic POSIX rename
- Worst case: missing new file (not corrupted live file)

### 3. Parent-Shell Retries — No Subshells
```bash
# Instead of: out=$(retry cmd)
durable::retry 3 5 cmd arg... >/tmp/out 2>&1 || rc=$?
```
- Retry loop runs in **current shell**, not command substitution
- Signal 36 kills the child, **not the retry loop**

---

## Installation

```bash
# Clone
git clone https://github.com/yourname/durable-sh.git
# Or copy just the library
curl -sSL https://raw.githubusercontent.com/yourname/durable-sh/main/lib/durable.sh -o /usr/local/lib/durable.sh

# In your script:
source /usr/local/lib/durable.sh
# That's it — signal 36 guard installs automatically
```

**Requirements:** bash 4.0+, Linux (tested on Android/bionic, glibc, musl, alpine)

---

## Quick Start

```bash
#!/usr/bin/env bash
source /path/to/durable.sh

# 1. Atomic write (survives kill mid-write)
durable::atomic_write_str /etc/myapp/config.json '{"port":8080}'

# 2. Retry with logging (parent shell, not subshell)
durable::run git commit -m "update"

# 3. Verified git push (real exit code, not tail)
durable::git_push_retry origin main

# 4. Stale lock auto-clear (safe: only when no git alive)
durable::git_clear_stale_lock

# 5. Daemon supervision (PID file + restart)
durable::daemon_ensure /var/run/mydaemon.pid /var/log/mydaemon.log \
  mydaemon --config /etc/myapp/config.json
```

---

## API Reference

### Core
| Function | Description |
|----------|-------------|
| `durable::install_sig36_guard` | Install `trap '' 36` (auto-called on source) |
| `durable::init` | `set -euo pipefail` + guard + PATH (auto-called) |

### Atomic I/O
| Function | Description |
|----------|-------------|
| `durable::atomic_write <target>` | Read stdin → temp → mv to target |
| `durable::atomic_write_str <target> <str>` | Write string atomically |
| `durable::atomic_append <target>` | Append stdin atomically |

### Retry (Parent Shell)
| Function | Description |
|----------|-------------|
| `durable::retry <max> <delay> <cmd> [args...]` | Retry in current shell, logs to stderr |
| `durable::run <cmd> [args...]` | Shortcut: 3 attempts, 5s delay |

### Git Hardening
| Function | Description |
|----------|-------------|
| `durable::git_clear_stale_lock [repo]` | Remove `.git/index.lock` if no git processes (5s grace) |
| `durable::git_commit_retry <msg> [repo]` | Commit with retry + diff_rc handling |
| `durable::git_push_retry <remote> <branch>` | Push with retry, captures output, tests real rc |

### Verification
| Function | Description |
|----------|-------------|
| `durable::require_output <regex> <cmd> [args...]` | Fail if empty or no regex match |
| `durable::git_verify_remote_sha <remote> <ref>` | Get valid 40-hex SHA or fail |

### Supervision
| Function | Description |
|----------|-------------|
| `durable::pid_alive <pidfile>` | Check if PID file points to living process |
| `durable::daemon_ensure <pidfile> <logfile> <cmd> [args...]` | Start/restart daemon with PID file |

---

## Why This Works

| Pattern | Mechanism | Survives Signal 36? |
|---------|-----------|---------------------|
| `trap '' 36` | `SIG_IGN` inherited, unresetable | ✅ All descendants |
| `tmp → mv` | Atomic rename on same FS | ✅ Worst case: missing file |
| Parent-shell retry | Loop not in subshell | ✅ Loop survives child death |
| `pgrep` lock check | Only clears when zero git alive | ✅ No false clears |
| `require_output` | Empty = inconclusive | ✅ No silent success |

---

## Real-World Provenance

Extracted from **[dev-lab-memory](https://github.com/digivasserver-ai/dev-lab-memory)** — a continuous memory system running on **Android 16 / Termux / proot** (Samsung S24 FE, Exynos 2400) where:

- `map_storage_loop.sh` + `relay_watch.sh` run 24/7 via 30-min cron
- `memory_sync.sh` pushes to GitHub + GitLab every 30 min
- `devlab_init.sh` restarts loops on demand
- **Zero data loss** since Signal-36 hardening (2026-10-06)

---

## Testing

```bash
# Run test suite
cd durable-sh
./tests/run_tests.sh
```

---

## License

MIT — see [LICENSE](LICENSE)

---

## Related

- [Signal 36 Root Cause Analysis](https://github.com/digivasserver-ai/dev-lab-memory/wiki/SIGNAL-36) — `traced_perf` deep dive
- [Letta: "Is a Filesystem All You Need?"](https://www.letta.com/blog/benchmarking-ai-agent-memory/) — filesystem beats vector DB for agent memory
- [MemGPT Paper](https://arxiv.org/abs/2310.08560) — OS-inspired memory hierarchy