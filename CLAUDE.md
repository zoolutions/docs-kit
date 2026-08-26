# docs-kit

Shared [Phlex](https://www.phlex.fun) chrome for documentation sites built on
[daisyUI](https://daisyui.com) — the shell, sidebar, code blocks, theme switcher,
and page kit extracted into one gem so multiple docs sites look identical and are
maintained in one place.

## Tech Stack

- **Ruby**: >= 3.2 | **Rails**: >= 7.1 (engine)
- **Rendering**: phlex-rails (Phlex 2) — the chrome is `DocsUI::` components
- **Styling**: daisyUI (via the `daisyui` gem) on Tailwind CSS v4, built with the standalone CLI (Bun)
- **Icons**: lucide via `rails_icons`
- **Highlighting**: Rouge (~200 languages), inline theme CSS
- **Client**: ONE Stimulus controller (`docs-nav`) auto-pinned by the engine
- **Autoloading**: zeitwerk
- **Testing**: RSpec (component render + registry + generator)
- **Linting**: RuboCop (`rubocop`)

## Critical Rules

### Never Do
1. **NO raw daisyUI markup** — the chrome is composed from `DocsUI::` Phlex components; a site never hand-writes drawer/menu HTML
2. **NO hardcoded site-specific values in a component** — brand, themes, nav, version badge come from `DocsKit.configuration`
3. **NO JS-required pages** — the server renders a working, fully-expanded page; the `docs-nav` controller only *enhances* (collapse persistence, auto-TOC). It must work with JS off
4. **NO per-feature Stimulus controllers** — there is exactly ONE (`docs-nav`), auto-pinned by the engine
5. **NO theme in `config.themes` that the CSS build never generated** — the switcher list MUST match the `@plugin "daisyui" { themes: ... }` block
6. **NO new emitted class without a CSS scan** — Tailwind scans Ruby; render-time classes (Drawer) need `@source inline(...)`
7. **NO `raw`/`html_safe` on config free text** — let Phlex escape text; only gem-authored trusted markup may bypass the escape
8. **NO required setup documented in the README alone** — wire it into the install generator AND the `docs-kit new` template, or new sites don't get it
9. **NO manual `gem push`** — release via `rake release[X.Y.Z]`

### Always Do
1. **TDD**: Write tests BEFORE implementation (RED → GREEN → REFACTOR)
2. **Read config, with a default** — a new knob lives on `DocsKit::Configuration` with a sensible default so existing sites keep working (backwards compatible)
3. **Compose from the kit** — new chrome is a `DocsUI::` component, not markup
4. **Render through a real view context** — `#render_page` renders with `layout: false` because `DocsUI::Shell` IS the whole document; CSRF, `dom_id`, url helpers, and (on reactive sites) the token signer must still work
5. **Keep the switcher and the CSS in sync** — themes offered == themes built
6. **Wire setup into the install path** — the generator templates and `docs-kit new` template, both
7. **Assert on semantics, not snapshots** — a component spec checks an active link / a present theme / a config-driven value, not a brittle full-HTML string

## Commands

```bash
bundle exec rspec        # Suite (component render + registry + config + generator)
bundle exec rubocop      # Lint (rubocop -A to autocorrect)
bundle exec rake         # spec + rubocop
bun run build:css        # Rebuild the Tailwind/daisyUI CSS (in a consuming site)
```

## Slash Commands

| Command | Purpose |
|---------|---------|
| `/plan` | Fable-powered planning → GitHub issue or `docs/plans/` markdown (read-only; execute with `/lfg`) |
| `/lfg` | Full autonomous workflow: branch → understand → explore → plan → TDD → verify → PR |
| `/tdd` | Enforce RED → GREEN → REFACTOR |
| `/architect` | Coordinate a change across config → registry → components → client → generator → CSS |
| `/security` | Security audit (HTML escaping, config trust, the render path, generated files, deploy secrets) |
| `/review-pr` | Review a PR for pattern compliance |
| `/github-review-pr` | Full PR pass: fix CI failures, then resolve review comments (in that order) |
| `/github-review-failures` | Fix failing CI checks until green |
| `/github-review-comments` | Process unresolved PR review comments |

## Architecture

```
Layer 4: Client runtime    app/javascript/docs_kit/controllers/docs_nav_controller.js (ONE controller: collapse persistence + auto-TOC + scroll-spy)
Layer 3: Components         app/components/docs_ui/*.rb (Shell, Sidebar, ThemeSwitcher, Icon, Code, Page, Header, Section, Prose, Callout, Example, OnThisPage)
Layer 2: Registry + values  lib/docs_kit/registry.rb (in-memory docs registry mixin), lib/docs_kit/nav_item.rb (sidebar link value object)
Layer 1: Config + controller lib/docs_kit/configuration.rb (per-site knobs), lib/docs_kit/controller.rb (#render_page)
Layer 0: Core + engine      lib/docs_kit.rb, lib/docs_kit/engine.rb (auto-pins docs-nav, mounts the controller assets)
         Install path        lib/generators/docs_kit/install/ (install generator + templates), lib/docs_kit/templates/new_site.rb, exe/docs-kit (docs-kit new)
         Deploy              .github/workflows/deploy.yml (reusable), deploy-docs.yml (thin caller); dash + GHCR + Cloudflare Tunnel
```

## The mental model

> Every docs site gets the SAME chrome. What differs between two sites is
> **configuration**, not markup. A component reads `DocsKit.configuration`; the
> server renders a working page; the one `docs-nav` controller enhances it.

Client interactivity is client-only UX polish (which `<details>` you left open,
the "on this page" TOC) — there is no server round-trip. See `README.md`.

## Model tiers (for Claude Code commands & agents)

Commands and agents pin a model **tier** via frontmatter aliases, not a full
model ID — aliases track the latest model in each tier, so pins never go stale:

- `haiku` — mechanical/config work, diff pattern-scans
- `sonnet` — layer specialists / pattern-following implementation (the default for `/tdd`, the review-comment/failure runbooks)
- `opus` — orchestration, security, production/PR review (`/lfg`, `/architect`, `/security`, `/review-pr`, `/github-review-pr`)
- `fable` — pinned only on `/plan` (read-only planning that hands execution to cheaper models); otherwise choose it per-session with `/model` for architecture and the hardest debugging

When spawning subagents for mechanical work (file finding, pattern scans), pass a
cheaper model explicitly (`model: haiku`) rather than letting them inherit the
session model. See `.claude/rules/agents.md`.

## Testing

- Unit specs (`spec/docs_kit/`) cover the config surface and the registry — no Rails boot.
- Component specs (`spec/docs_ui/`) render a `DocsUI::` component and assert on the produced markup's semantics (an active link, a present theme option, a config-driven value).
- Generator specs (`spec/generators/install_generator_spec.rb`) run `docs_kit:install` against a throwaway destination root (a tmp app skeleton, plain Thor — no Rails boot) and assert the file manifest + key contents.
- Coverage: SimpleCov enforces `minimum_coverage 80` from within the suite (`bundle exec rspec` / `rake` fails below it); 100% aspired for `DocsKit::Configuration` and `DocsKit::Registry` (the public API sites depend on).
- CI: `.github/workflows/ci.yml` runs `bundle exec rake` on Ruby 3.2/3.3/3.4 for every push to `main` and every PR.
- See `.claude/rules/testing.md`.

## Deploy

The build + deploy is defined **once** in this gem's reusable workflow
(`.github/workflows/deploy.yml`). `docs-kit new` scaffolds a thin caller. The
naming invariant: `image`/`service` must be the calling repo's `OWNER/REPO` so
`GITHUB_TOKEN` can push (build) and pull (deploy) the auto-linked GHCR package.
See the README "Deploy a new docs site" section for the five wiring points and
the naming note.

## More Documentation

- `.claude/commands/` — slash command definitions
- `.claude/rules/` — coding style, git workflow, testing, agents
- `README.md` — the full install/configure/render/deploy guide
