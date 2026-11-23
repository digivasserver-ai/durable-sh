# Changelog

## 0.2.0 - 2026-11-23

### Fixed
- `durable::git_clear_stale_lock`: fixed process detection. `pgrep -x 'git-*'` matched the literal pattern and missed real git helpers like `git-remote-https`; now scans `ps -eo comm=` for `^git(-.*)?$`. Added optional `grace_s` argument (default 5) for controlled/test flows.

### Added
- `durable::atomic_write`, `atomic_write_str`, `atomic_append`: optional `mode` argument (default `0644`). Atomic writes now chmod before rename, avoiding mkstemp 0600 leaking into git-tracked/generated files.
- `durable::pattern_alive <pgrep-f-pattern>`: pattern-based liveness check, preferred over pidfiles for daemons.
- `durable::git_mirror_parity <r1> <r2> [ref]`: verify two remotes resolve the same 40-hex SHA; returns inconclusive on empty/invalid remote SHA.

### Tests
- Test suite expanded (24 tests) covering mode, pattern liveness, and stale-lock clearing behavior.

## 0.1.0 - 2026-10-06
- Initial public release: signal 36 guard, atomic I/O, retry, git hardening, verification, pidfile supervision.
