# Lode map

The index of this repository's durable memory. Read this first; then the file that
covers the area you are changing. Every file states the system as it is now — no
changelog prose, no "known gaps" (those live in the PR that closes them).

## Baseline

| File | What it holds |
|---|---|
| [summary.md](summary.md) | What docs-kit is, who runs it, and the three invariants every change is measured against |
| [terminology.md](terminology.md) | The repo's own words — chrome, the kit, registry, the `page` DSL, authored page, Markdown twin, scope, snapshot, drift, synced stamp — each with the file that defines it |
| [practices.md](practices.md) | The patterns `.claude/rules/` does not state: absent-knob defaults, degrade-on-render, mtime-backed config, `#docs_config`, runtime-detected optional gems, the one enumeration seam, semantic generator idempotence, site-owned vs gem-owned files, literal Tailwind classes, Rails-free renders, `raw(safe(…))` |
| [workflow.md](workflow.md) | The profile the shared `/lode:` workflow skills read: commands, branches, layers, shapes, constraints, docs, CI, flake sources, conflicts, verification |
| [plans/README.md](plans/README.md) | Where a plan artifact goes |

## Areas

| File | Subsystem |
|---|---|
| [core/summary.md](core/summary.md) | `lib/docs_kit.rb` (zeitwerk loader), `engine.rb` (four initializers, no routes), `controller.rb` (`#render_page`), `scope.rb` / `scoping.rb` (the request axis) |
| [config/summary.md](config/summary.md) | `DocsKit::Configuration` — the 36 top-level knobs, the derived readers, and the `Data.define` value objects |
| [registry-and-versions/summary.md](registry-and-versions/summary.md) | `Registry` (the `page` DSL and the legacy `entries` API), `Registry::Entry`, `DocVersion`, `Snapshot` |
| [components/summary.md](components/summary.md) | The 30 `DocsUI::` Phlex classes plus `PageHelpers`, and the one `docs-nav` Stimulus controller |
| [ai-surfaces/summary.md](ai-surfaces/summary.md) | `MarkdownExport` (the twin), `LlmsText` + `/llms.txt`, `SearchIndex` + `/docs/search`, `McpTools` / `McpServer` + `POST /mcp`, the `OpenApi` bridge |
| [install-path/summary.md](install-path/summary.md) | `InstallGenerator` and its 16 templates, `SyncReport`, `Migration` / `MigrationRegistry`, `PageGenerator`, `exe/docs-kit`, `templates/new_site.rb`, the CSS contract, the shipped RuboCop cops |
| [testing-and-ci/summary.md](testing-and-ci/summary.md) | The RSpec suite's four layers, `ci.yml`'s three jobs, `rake release`, the reusable `deploy.yml`, and the `docs/` dogfood site |

## Review rules

Accepted review findings, rewritten as rules about the system. `/lode:gate`
enforces them; `/lode:learn` adds to them.

| File | Covers |
|---|---|
| [review/cli-and-templates.md](review/cli-and-templates.md) | `docs-kit new` and `lib/docs_kit/templates/new_site.rb` — where a default must be changed, and why a template fallback is dead on the CLI path |

## Related, outside the lode

- `../CLAUDE.md` — the project brief, the critical-rules lists, the layer map
- `../AGENTS.md` — the cross-tool orientation and the page-authoring contract
- `../.claude/rules/` — coding-style, git-workflow, testing, agents, seo
- `tmp/` — scratch for a run in progress; gitignored, never committed
