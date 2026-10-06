# tests/

The full suite (`run_tests.sh`, 435 passing) and `review-checks.sh` were
removed on 2026-10-06: they cost more CI time than they saved at this stage
of the project. Both remain in git history and can be restored from there.

Policy from here on: **a new feature ships with its own focused test**, not a
resurrection of the suite. Put it here as `tests/<feature>.sh`, self-contained
(exit non-zero on failure, silent on success), following the rules that made
the old suite trustworthy:

- Drive the real CLI (`bin/hyprx`), never grep the source for a function name.
  A test that passes when the behaviour is broken is worse than no test.
- Assert exit codes *and* output together. "Did not abort" and "did not lie
  about success" are different assertions.
- Hermetic: sandbox with `HYPRX_STATE_DIR` / `HYPRX_CLEAN_ROOT` /
  fixture `PATH` stubs. A test that mutates the real machine is a liability.
- No network. Fixtures, not downloads: an outage must not read as a
  regression.
