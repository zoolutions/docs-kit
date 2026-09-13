# Plans

Plan artifacts for docs-kit go to **GitHub issues on `zoolutions/docs-kit`** —
that is the default and the one that feeds execution (`/lode:lfg <issue-number>`
reads the issue body as its brief). Label and milestone the issue the way the
tracker already does; dedupe with `gh issue list --search "<keywords>"` before
opening a new one.

A file-backed plan (`/lode:plan --file`) is written here, as
`lode/plans/YYYY-MM-DD-<slug>.md`. Use it only when the plan should not be public
or is a working draft that will become an issue.

`docs/plans/` does **not** exist in this repository, despite what the retired
`/plan` command and `.claude/README.md` said. `docs/` is the dogfood Rails app;
nothing under it is a plan.

A plan is self-contained: an executor with none of the planning session's context
must be able to implement it without guessing. Sections, in order — Context (what
was read and what it says), Decision (the chosen approach and why the others
lost), Steps (specs named before implementation), Gates (the commands that must
pass), Boundaries (what this change must not touch).
