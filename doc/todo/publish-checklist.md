# Pre-publish checklist

Before pushing this repo to a public location.

## Strip personal info

- `skel/home/.config/git/config` lines 2–3 contain real name `Jan Kotek` and
  email `jan@kotek.net`. Decide: keep (publishing under that identity
  anyway), or templatize.
- `test/vm/dotfiles.bats:56,60` hardcode the same name/email in
  assertions. Update to match whatever is decided above.
- `doc/todo/monitors.md` references the name `adam` (third-party) and the
  path `/home/playai`. Plan: strip the entire `doc/todo/` directory before
  publishing (this file included).

## Strip git history

History mixes two authors: `Jan Kotek <jan@kotek.net>` and
`Claude <claude@anthropic.com>` (11 early commits). Rewrite with a mailmap
or `git filter-repo` if a single authorship is desired.

## Verify no static timestamps

Confirmed during review: no hardcoded dates anywhere. Only runtime
expressions like `$(date +%y%m%d-%H%M%S)` in tests — those are fine.
