# `.claude/` — docs-kit engineering toolkit

Slash commands and rules that drive autonomous and semi-autonomous work on
docs-kit. The full loop is `/lode:lfg`, from the `lode@zoolutions` plugin enabled
in `settings.json`; the commands below are the repo-specific specialists that
remain here. The plugin reads `../lode/workflow.md` for everything specific to
this repository.

## Commands

| Command | Tier | Purpose |
|---------|------|---------|
| `/architect` | `opus` | Coordinate a change across config → registry → components → client → generator → CSS |
| `/security` | `opus` | Security audit (HTML escaping, config trust, render path, generated files, deploy secrets) |
| `/review-pr` | `opus` | Review a PR for docs-kit pattern compliance |

Retired in favour of the plugin: `/plan` → `/lode:plan`, `/lfg` → `/lode:lfg`,
`/tdd` → `/lode:tdd`, `/github-review-pr` → `/lode:review-pr`,
`/github-review-failures` and `/github-review-comments` → phases of
`/lode:review-pr`. Their repo-specific content — the conflict rules, the CI
quirks, the constraint tables — moved to `../lode/workflow.md`.

## Rules

`rules/` holds the project conventions the commands lean on:

- `coding-style.md` — many small files, compose from `DocsUI::` components, read config, progressive enhancement
- `git-workflow.md` — conventional commits, branch naming, PR flow, `rake release`
- `testing.md` — the test layers (config / component render / generator), coverage bars
- `seo.md` — the SEO/OG meta-tag contract
- `agents.md` — when to delegate, parallel exploration, cheaper models for mechanical subagents

## Model-tier convention

Every command (and agent) pins a model **tier alias** in its frontmatter, never a
full model ID:

```markdown
---
description: "..."
model: sonnet   # haiku | sonnet | opus | fable
argument-hint: "..."
---
```

- `haiku` — mechanical/config work, diff pattern-scans
- `sonnet` — layer specialists / pattern-following implementation (the default)
- `opus` — orchestration, security, PR/production review
- `fable` — read-only planning that hands execution to cheaper models; otherwise pick it per-session with `/model`

Aliases track the latest model in each tier, so a pin never goes stale the way a
literal `claude-opus-4-8` does. When you author a new command, pick the tier by
the work it does, and pass a cheaper `model:` explicitly to any subagent doing
mechanical work rather than letting it inherit the session model.
