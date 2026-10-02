---
description: Adopt or upgrade the zoolutions release kit (bin/release + rakelib/release.rake + release.yml) in one or more sibling gem checkouts, one PR per repo
model: opus
argument-hint: "../gem-a ../gem-b (sibling checkouts; empty = every gem listed in RELEASE_KIT.md)"
---

# Release kit rollout

Bring each target gem onto the release kit whose canonical copy is THIS repo
(docs-kit). Read `RELEASE_KIT.md` first; it is the spec for everything below.

Targets: `$ARGUMENTS`. When empty, use every gem in RELEASE_KIT.md's "Gems on the
kit" list, resolved as sibling checkouts (`../<name>`).

## 0. Preconditions (docs-kit)

- docs-kit must be on an up-to-date `main` with a clean tree: the kit you copy is
  what's merged, never a feature branch. If not, stop and say so.
- `script/release-kit check <targets>` shows where each target stands.

## 1. Per target (independent; fan out one subagent per repo when there are several)

In the target checkout:

1. Refuse a dirty tree. `git fetch origin && git switch -c chore/release-kit origin/<default branch>`.
2. `<docs-kit>/script/release-kit sync .`
3. **First adoption** (sync said "wrote the canonical release.yml"): port the
   repo's old release `test` job into the new file's `test` job. Keep its
   commands, matrix and services. Apply the test-job rules from RELEASE_KIT.md,
   including the frozen `bundle install`. Carry over anything else the old
   workflow did that the kit doesn't; if you can't, list it in the PR.
4. **Rakefile**: delete the old `task :release` and helpers only it used. Diff the
   old task against `rakelib/release.rake` step by step. Move every project-only
   step into a `release:preflight` / `release:prepare` hook, or list it as a
   deviation. Add `rakelib` to explicit `RuboCop::RakeTask` patterns.
5. Old `bin/release` or release scripts: replaced by the kit. Carry over any
   project-only check as a hook.
6. RuboCop must pass on `rakelib/release.rake`. When a repo cop conflicts with the
   shared file (it stays Ruby 3.2-compatible), exclude that file from that one
   cop, with a comment. NEVER edit the kit files in the target: if a kit file
   needs a change, stop that repo and report it (it goes into docs-kit first).
7. Docs: point README / AGENTS.md / CLAUDE.md / `.claude/**` / RELEASING.md at
   `bin/release`. Make sure no doc claims a guarantee the kit doesn't give.
8. Verify, and report real output:
   - the repo's suite + `bundle exec rubocop`
   - `bin/release --help`, `bin/release list`, `bin/release --dry-run`
   - `bundle exec rake -T | grep release`
   - `zizmor .github/workflows/release.yml` (and actionlint when the repo's CI
     runs it; declare `ubuntu-26.04` in `.github/actionlint.yaml` if it's unknown)
   - `<docs-kit>/script/release-kit check .` shows "in sync"
   - **sandbox release**: bare-clone the repo into the scratchpad, put a fake
     `gh` (logs its args; `release view` exits 1) first on PATH, run
     `rake "release[<next patch>]"` with `BUNDLE_GEMFILE` at the real checkout.
     The commit must contain exactly version.rb + the gem's lockfile pins (+ what
     `release:prepare` writes). If there's a preflight hook, prove it aborts
     with a clean tree.
9. Commit (`chore(release): adopt the zoolutions release kit` or `…: sync the
   release kit`), push, `gh pr create --label chore --label devops` with summary, test plan, and a
   `## Deviations & judgment calls` section. Watch CI to green and fix what you
   broke.

## 2. Close out

- Adopting a new gem: add it to RELEASE_KIT.md's list in a docs-kit PR.
- Report a table: repo, PR URL, CI state, `script/release-kit check` result,
  deviations. Don't call a repo done until its CI is green.
