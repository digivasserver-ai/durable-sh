# Credits

## durable-sh — Signal-36 Hardened Shell Primitives

### Investigation & Root Cause Discovery (Signal-36 / traced_perf)

| Role | Session | Model |
|------|---------|-------|
| **Forensic Analysis** — Identified `BIONIC_SIGNAL_PROFILER` (signal 36) sent by Android's `traced_perf`; verified via `bionic/reserved_signals.h`, `/system/etc/init/traced_perf.rc`, live process observation (PID 8285) | `ses_ef7cd8252ffeg26Z6cnC9xYZsX` (2026-10-04) | `big-pickle` (OpenCode) |
| **Experimental Validation** — Designed & executed N=100 controlled trials proving `trap '' 36` reduces kills from 10/240 → 1/240; documented immunity threshold (<20ms), plateau (~15%), `setsid`/`nohup` ineffectiveness | `ses_ef7cd8252ffeg26Z6cnC9xYZsX` | `big-pickle` (OpenCode) |
| **Documentation** — Authored `wiki/SIGNAL-36.md`, `PLAYBOOK.md` VERIFIED entries with reproduction commands | `ses_ef7cd8252ffeg26Z6cnC9xYZsX` / `ses_ef784261bffeiscME1fAS5QL3w` | `big-pickle` / `muse-spark-1.3-contributor-free (xhigh)` (OpenCode) |

### Library Engineering & Publication

| Role | Session | Model |
|------|---------|-------|
| **Library Design** — Extracted 3 hardening patterns (`trap '' 36`, tmp→mv atomic writes, parent-shell retries) into reusable `durable.sh` | `ses_eed88dc3cffeeEUnfCyzJTJe34` (2026-10-06) | `fledge-alpha-free (max)` (OpenCode) |
| **Implementation** — 250-line `lib/durable.sh` with 11 functions: signal guard, atomic I/O, retry loops, git hardening, verification, daemon supervision | `ses_eed88dc3cffeeEUnfCyzJTJe34` | `fledge-alpha-free (max)` (OpenCode) |
| **Test Suite** — 18 comprehensive tests covering all functions, `set -e` safe counters, CI-ready runner | `ses_eed88dc3cffeeEUnfCyzJTJe34` | `fledge-alpha-free (max)` (OpenCode) |
| **Documentation** — README.md with API reference, provenance, testing instructions | `ses_eed88dc3cffeeEUnfCyzJTJe34` | `fledge-alpha-free (max)` (OpenCode) |
| **Release & Publication** — Git history, MIT license, GitHub repository creation, savepoint tagging | `ses_eed88dc3cffeeEUnfCyzJTJe34` | `fledge-alpha-free (max)` (OpenCode) |

### Lab Infrastructure (Foundation)

| Component | Owner |
|-----------|-------|
| Dev lab memory layer (MEMORY.md, MASTER_MAP.md, audit.jsonl, dual git mirrors, Mega byte store) | digivasserver-ai |
| Signal-36 hardened automation (`devlab_init.sh`, `memory_sync.sh`, `savepoint.sh`, `map_storage_loop.sh`) | digivasserver-ai + OpenCode assistants |
| Android/Termux/proot environment (Samsung S24 FE, Exynos 2400, Android 16) | digivasserver-ai |

---

## Attribution Summary

> **Root cause discovery credit:** OpenCode AI Assistant (`big-pickle`) — forensic investigation, source-code verification, controlled experiments, technical documentation.
>
> **Engineering & publication credit:** digivasserver-ai (direction, architecture, release) + OpenCode AI Assistant (`fledge-alpha-free`) — library implementation, test suite, packaging, public release.
>
> **Legal ownership:** digivasserver-ai (work made for hire / tool output).

---

## Citation

If you use `durable-sh` in academic or technical work:

```bibtex
@software{durable-sh,
  title = {durable.sh — Signal-36 Hardened Shell Primitives},
  author = {digivasserver-ai and OpenCode AI Assistant},
  year = {2026},
  url = {https://github.com/digivasserver-ai/durable-sh},
  note = {Root cause discovery: Android traced_perf/BIONIC_SIGNAL_PROFILER (signal 36); Hardening patterns: inherited SIG_IGN, atomic tmp→mv writes, parent-shell retry loops}
}
```

---

## License

MIT — see [LICENSE](LICENSE). Attribution appreciated but not required.