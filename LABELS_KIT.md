# The zoolutions labels kit

Every zoolutions repository labels its issues and pull requests the same way:
one `type`, at least one `area`, `status` only on issues. Each repo declares its
labels in `.github/labels.yml`, and `bin/labels sync` makes GitHub match it.
docs-kit holds the canonical copy of the kit; `script/labels-kit` copies it into
the other repos and checks them for drift.

| File | Shared how | What it does |
|---|---|---|
| `bin/labels` | verbatim | `sync` GitHub to the manifest, `infer` areas from paths, `migrate` a label away, `validate` the manifest |
| `.github/LABELS.md` | verbatim | The rules: groups, the type table, how to label a PR, how to retire a label |
| `.github/labels.yml` | shared labels + the repo's own areas | Every label outside the `area` group (type, status, community) is byte-for-byte docs-kit's. `devops`, `dx` and `docs-site` are shared areas, carried unchanged where they apply. The other areas, the `paths:` map and `ignore:` are the repo's own |

`bin/labels` is plain Ruby with no gems beyond the standard library, talks to
GitHub only through `gh`, and stays Ruby 3.1-compatible (importmap-plus is the
lowest floor). Its specs live here only (`spec/labels_kit/`), like `bin/release`.

## Repos on the kit

daisyui, dash, dash-proxy, docs-kit (canonical), glyphs, importmap-plus,
locallingo, pgbus, phlex-forms, phlex-reactive, sidekiq-unique-jobs, stationery.

## The taxonomy

The shared groups are defined once, in this repo's `.github/labels.yml`:

- **type** (exactly one): `bug`, `enhancement`, `performance`, `tech-debt`,
  `security`, `documentation`, `dependencies`, `chore`
- **status** (issues only): `plan`, `epic`, `blocker`, `needs-info`. A repo may
  add its own (dash's `flaky-test`)
- **community**: GitHub's defaults (`good first issue`, `help wanted`,
  `question`, `duplicate`, `invalid`, `wontfix`), kept because GitHub surfaces
  them to contributors
- **source** and **legacy**: a repo's own, when it has them (an origin such as a
  bot, or labels kept for history but never applied again)

Areas are the repo's architecture: derive them from its conventional-commit
scopes and its `lib/` layout, and give each one path globs where a path is a
reliable signal.

## Wiring the commands

A repo on the kit labels from its slash commands, so labelling isn't left to
memory:

- `/plan` labels the issue it files: `plan` + one type + the areas from
  `bin/labels infer <paths in the plan>`
- `/lfg` carries the issue's type + areas onto the pull request
  (`gh pr create --label …`), or infers them for a description-only run
- every other command that runs `gh pr create` / `gh issue create` passes
  labels too
- `.claude/rules/git-workflow.md` and `AGENTS.md` state the rule
- `.github/dependabot.yml` gives every update an explicit `labels:` list, so
  dependabot stops creating its own ecosystem labels (`ruby`, `github_actions`)
  that the sync would otherwise delete again

## Adopting the kit in a repo

1. Branch from a fresh `main`, then `script/labels-kit sync ../the-repo`. A repo
   with no `.github/labels.yml` gets a starter holding the shared labels.
2. Read the repo's history (`gh label list`, `gh pr list --state all --json
   title,labels,files`): its commit scopes and touched directories become the
   areas; labels in use become a mapping onto the taxonomy.
3. Write the areas and `paths:` into `.github/labels.yml`. Labels some
   automation owns go in `ignore:`.
4. `bin/labels validate`, then `bin/labels sync --dry-run` to see the plan.
5. Re-label before deleting: `bin/labels migrate <old> <new…>` for each label
   the taxonomy replaces (`bugfix` → `bug`), then `bin/labels sync --delete`; it
   refuses any label still on an item, open or closed. A label whose history is
   worth keeping but that has no future stays in the manifest under `legacy`.
6. Wire the commands (above), `bin/labels sync`, and open the PR with its own
   labels: `--label chore --label dx`.
7. `script/labels-kit check ../the-repo` (from docs-kit) shows "in sync".

## Changing the kit

Change `bin/labels`, `.github/LABELS.md` or a shared label here, with specs,
then `script/labels-kit sync <repos>` and open a PR per repo.

`sync` copies only the verbatim files; it never rewrites a repo's existing
`.github/labels.yml`, which is the repo's own. So a shared-label change has to
be written into each repo's manifest by hand in that repo's PR —
`script/labels-kit check` names every repo still carrying the old label — and
then pushed to GitHub with `bin/labels sync` there.

One blind spot: `check` lets a repo add its own `status` labels, so it can't
tell a retired shared status label from a repo-specific one. When a shared
status label is renamed or retired, `grep -l '<old name>' ../*/.github/labels.yml`
across the repos and remove it (after `bin/labels migrate`) in each repo's PR.
