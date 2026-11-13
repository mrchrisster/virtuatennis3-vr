# One-command build from the player's copy (2026-11-13)

Owner's decision: the app stays free of game data and the APK is never
published, so each player builds their own from their own copy. This is the
work log for `scripts/build-quest-from-my-copy.sh` and the test / CI clean-up
that came with it.

## Plan / progress

- [ ] `scripts/build-quest-from-my-copy.sh <disk0> [--install] [--mac] [--check]`
- [ ] `scripts/build-macos.sh`: `--lift-only`, lift skipped when current
  (`generated/.lift-stamp`), Python 3.10+ search, `requirements-dev.txt`
- [ ] `games/vt3/game.conf`: `ELF_SHA256`, `SOLIBS_EXPECTED` (fingerprints)
- [ ] tests: `test_xr_actions` (selftest stubs for the thumbstick action
  added in lindberghrecomp 20f9a90), `test_solib_relocs` skip without
  pyelftools, OpenXR header search, main guards
- [ ] CI: unittest discovery, OpenXR headers fetched, script `--help` / lint
- [ ] README: one-command path, manual steps collapsed, troubleshooting
- [ ] proof: fresh clone + fresh deps dir -> APK on this Mac, headless
