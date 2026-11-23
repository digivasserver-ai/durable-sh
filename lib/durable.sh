#!/usr/bin/env bash
# durable.sh — Signal-36 hardened shell primitives
# Source this file: source /path/to/durable.sh
# Requires: bash 4.0+, Linux (tested on Android/bionic, glibc, musl)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CORE: Signal 36 (BIONIC_SIGNAL_PROFILER) protection
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Ignore SIGRTMIN+2 (signal 36 on Android/bionic) — inherited across fork+exec
# and CANNOT be reset by children (unlike other dispositions).
# This single line protects every descendant process from traced_perf kills.
durable::install_sig36_guard() {
  trap '' 36
}

# Install guard immediately when sourced (idempotent)
durable::install_sig36_guard

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ATOMIC WRITES: tmp → mv pattern (survives mid-write kills)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Write stdin to file atomically: durable::atomic_write /path/to/file [mode] < data
# Uses temp file on same filesystem + mv (atomic on POSIX). Default mode 0644
# (mkstemp creates 0600; git-tracked/generated files usually need 0644).
durable::atomic_write() {
  local target="$1" mode="${2:-0644}"
  local tmp dir
  dir="$(dirname -- "$target")"
  tmp="$(mktemp "${dir}/.durable.tmp.XXXXXX")" || return 1
  cat >"$tmp" || { rm -f "$tmp"; return 1; }
  chmod "$mode" "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$target"
}

# Write string atomically: durable::atomic_write_str /path/to/file "content" [mode]
durable::atomic_write_str() {
  local target="$1" content="$2" mode="${3:-0644}"
  printf '%s' "$content" | durable::atomic_write "$target" "$mode"
}

# Append atomically: durable::atomic_append /path/to/file [mode] < data
# Note: read+write is not concurrency-safe; use only for single-writer logs.
durable::atomic_append() {
  local target="$1" mode="${2:-0644}"
  local tmp dir
  dir="$(dirname -- "$target")"
  tmp="$(mktemp "${dir}/.durable.tmp.XXXXXX")" || return 1
  if [[ -f "$target" ]]; then
    cat "$target" >"$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  fi
  cat >>"$tmp" || { rm -f "$tmp"; return 1; }
  chmod "$mode" "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$target"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# RETRY LOOPS: Parent-shell only (subshells die with signal 36)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Run command with retries in CURRENT shell (not subshell).
# Usage: durable::retry 3 5 cmd arg1 arg2...
#   $1 = max attempts (default 3)
#   $2 = delay seconds between attempts (default 5)
#   $3... = command + args
# Returns: exit code of last attempt; prints attempt logs to stderr
durable::retry() {
  local max_attempts="${1:-3}" delay="${2:-5}" attempt=1 rc=0
  shift 2 || { echo "durable::retry: usage: max_attempts delay cmd [args...]" >&2; return 64; }
  local out_file
  out_file="$(mktemp "/tmp/durable.retry.XXXXXX")" || return 1

  while (( attempt <= max_attempts )); do
    rc=0
    "$@" >"$out_file" 2>&1 || rc=$?
    if (( rc == 0 )); then
      echo "[retry] ok (try $attempt/$max_attempts)" >&2
      cat "$out_file"
      rm -f "$out_file"
      return 0
    fi
    if (( attempt < max_attempts )); then
      echo "[retry] rc=$rc (try $attempt/$max_attempts), retrying in ${delay}s" >&2
      sleep "$delay"
    else
      echo "[retry] FAILED rc=$rc after $max_attempts tries — see $out_file" >&2
      tail -3 "$out_file" >&2
    fi
    ((attempt++))
  done
  rm -f "$out_file"
  return "$rc"
}

# Convenience: run with default 3 attempts, 5s delay
durable::run() {
  durable::retry 3 5 "$@"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# GIT HARDENING: Stale lock clearing, verified push
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Clear .git/index.lock if no git process is alive.
# Safe: only removes lock when zero git/git-* processes exist (5s grace).
# Checks process comm names exactly (git, git-remote-https, git-receive-pack, ...).
durable::git_clear_stale_lock() {
  local repo_root="${1:-.}" grace="${2:-5}"
  local lock_file="$repo_root/.git/index.lock"
  [[ -f "$lock_file" ]] || return 0

  # Grace for normal git exit; callers can pass 0 in tests/controlled flows.
  (( grace > 0 )) && sleep "$grace"
  # Match git and git-* by comm name. pgrep -x 'git-*' is literal and misses
  # git-remote-https; use ps comm scan for portability across procps variants.
  if ! ps -eo comm= 2>/dev/null | grep -Eq '^git(-.*)?$'; then
    echo "[git] clearing stale index.lock (no git processes alive)" >&2
    rm -f "$lock_file"
    return 0
  fi
  return 1
}

# Commit with retry and proper exit-code handling.
# Distinguishes: rc=0 (nothing staged) vs rc=1 (staged) vs rc>1 (error/kill).
durable::git_commit_retry() {
  local msg="$1" repo_root="${2:-.}" attempt=1 rc=0 diff_rc=0
  cd "$repo_root" || return 1
  durable::git_clear_stale_lock

  while (( attempt <= 3 )); do
    { git diff --cached --quiet; diff_rc=$?; } || true
    if (( diff_rc == 0 )); then
      echo "[git] nothing staged (try $attempt)" >&2
      return 0
    elif (( diff_rc > 1 )); then
      echo "[git] diff failed rc=$diff_rc (try $attempt)" >&2
    else
      { git commit -m "$msg" >/dev/null 2>&1 && { echo "[git] committed (try $attempt)" >&2; return 0; }; rc=$?; } || true
      echo "[git] commit rc=$rc (try $attempt)" >&2
    fi
    (( attempt < 3 )) && sleep 5 || break
    ((attempt++))
    durable::git_clear_stale_lock
  done
  return 1
}

# Push with retry; captures output, tests real git exit code (not tail).
durable::git_push_retry() {
  local remote="${1:-origin}" branch="${2:-HEAD}" attempt=1 rc=0 out_file
  out_file="$(mktemp "/tmp/durable.push.XXXXXX")"
  while (( attempt <= 3 )); do
    git push "$remote" "$branch" >"$out_file" 2>&1
    rc=$?
    if (( rc == 0 )); then
      echo "[git] pushed to $remote/$branch (try $attempt)" >&2
      cat "$out_file"
      rm -f "$out_file"
      return 0
    fi
    echo "[git] push rc=$rc (try $attempt)" >&2
    (( attempt < 3 )) && sleep 5 || break
    ((attempt++))
  done
  echo "[git] push FAILED after 3 tries — see $out_file" >&2
  cat "$out_file" >&2
  rm -f "$out_file"
  return 1
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# VERIFICATION: Empty result = inconclusive (never trust silent success)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Run command; fail if output empty or doesn't match regex.
# Usage: durable::require_output "regex" cmd arg...
# Returns: 0 if output non-empty AND matches regex; 1 if empty; 2 if no match; cmd_rc if cmd failed
durable::require_output() {
  local pattern="$1" out_file rc
  shift
  out_file="$(mktemp "/tmp/durable.verify.XXXXXX")"
  "$@" >"$out_file" 2>&1
  rc=$?
  if (( rc != 0 )); then
    echo "[verify] command failed rc=$rc" >&2
    cat "$out_file" >&2
    rm -f "$out_file"
    return "$rc"
  fi
  local output
  output="$(cat "$out_file")"
  rm -f "$out_file"
  [[ -n "$output" ]] || { echo "[verify] empty output — INCONCLUSIVE" >&2; return 1; }
  [[ "$output" =~ $pattern ]] || { echo "[verify] output doesn't match pattern — INCONCLUSIVE" >&2; return 2; }
  echo "$output"
  return 0
}

# Verify git ls-remote returns a valid 40-hex SHA
durable::git_verify_remote_sha() {
  local remote="${1:-origin}" ref="${2:-refs/heads/master}"
  durable::require_output '^[0-9a-f]{40}$' git ls-remote "$remote" "$ref" | awk '{print $1}'
}

# Check that two remotes point at the same commit for a ref. Returns 0 if equal.
# Prints "equal <sha>" or "diverged <r1>=<sha1> <r2>=<sha2>" to stdout.
durable::git_mirror_parity() {
  local r1="${1:-origin}" r2="${2:-gitlab}" ref="${3:-refs/heads/master}"
  local s1 s2
  s1="$(git ls-remote "$r1" "$ref" 2>/dev/null | awk '{print $1}')"
  s2="$(git ls-remote "$r2" "$ref" 2>/dev/null | awk '{print $1}')"
  [[ "$s1" =~ ^[0-9a-f]{40}$ ]] || { echo "inconclusive $r1"; return 2; }
  [[ "$s2" =~ ^[0-9a-f]{40}$ ]] || { echo "inconclusive $r2"; return 2; }
  if [[ "$s1" == "$s2" ]]; then
    echo "equal $s1"
    return 0
  fi
  echo "diverged $r1=$s1 $r2=$s2"
  return 1
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PROCESS SUPERVISION: PID file liveness + restart
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Check if PID file points to living process.
# Note: pidfiles can be stale (non-empty but dead) or missing while live; prefer
# durable::pattern_alive for long-running daemons when a stable pattern exists.
durable::pid_alive() {
  local pid_file="$1"
  [[ -f "$pid_file" ]] || return 1
  local pid
  pid="$(cat "$pid_file" 2>/dev/null)" || return 1
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# Check for a living process by pgrep -f pattern. Prefer this over pidfiles for
# daemons; patterns survive pidfile loss/staleness (DEFECT-16 class).
durable::pattern_alive() {
  local pattern="$1"
  [[ -n "$pattern" ]] || return 1
  pgrep -f -- "$pattern" >/dev/null 2>&1
}

# Start/restart a daemon with PID file management
# Usage: durable::daemon_ensure /path/to/pidfile /path/to/logfile cmd arg...
# Verifies daemon stays alive for 2s after start.
durable::daemon_ensure() {
  local pid_file="$1" log_file="$2"
  shift 2
  if durable::pid_alive "$pid_file"; then
    echo "[daemon] alive pid=$(cat "$pid_file")" >&2
    return 0
  fi
  echo "[daemon] starting..." >&2
  setsid nohup "$@" >"$log_file" 2>&1 < /dev/null &
  local pid=$!
  echo "$pid" >"$pid_file"
  # Verify it stays alive briefly
  sleep 2
  if kill -0 "$pid" 2>/dev/null; then
    echo "[daemon] started pid=$pid (verified alive)" >&2
    return 0
  else
    echo "[daemon] FAILED: pid=$pid died immediately" >&2
    rm -f "$pid_file"
    return 1
  fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# INIT: Call once at script start
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Install all guards, set safe defaults
# DURABLE_PATH_EXTRA: colon-separated paths to prepend to PATH (optional)
durable::init() {
  set -euo pipefail
  durable::install_sig36_guard
  [[ -n "${DURABLE_PATH_EXTRA:-}" ]] && export PATH="${DURABLE_PATH_EXTRA}:${PATH}"
  return 0
}

# Auto-init when sourced (can be disabled: DURABLE_NOINIT=1)
# Use || true to avoid triggering set -e when condition is false
[[ -z "${DURABLE_NOINIT:-}" ]] && durable::init || true

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# EXPORTS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# All functions are available after sourcing.
# No global state except the signal 36 trap (process-wide, inherited).