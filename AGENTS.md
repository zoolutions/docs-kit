# AGENTS.md

The instruction file for every AI coding agent working in docs-kit — Claude
Code imports it (`CLAUDE.md` is a one-line `@AGENTS.md` stub); Cursor,
Copilot, Aider, Codex and others read it directly. Claude Code also has
`.claude/commands/` and `.claude/rules/` for slash-command workflows, listed
below; this file stays the shared source of project conventions.

docs-kit is a Rails engine that ships the shared Phlex/daisyUI **chrome** for
documentation sites — the shell, sidebar, code blocks, theme switcher, page
kit — so many docs sites look identical and are maintained in one place. The
gem also **dogfoods itself**: its own docs site lives under `docs/`.

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
1. **TDD**: write the failing spec first — `spec/docs_kit/**` (config/registry, no boot), `spec/docs_ui/**` (component render), `spec/generators/install_generator_spec.rb` (generator, plain Thor) — then the minimum code (RED → GREEN → REFACTOR)
2. **Read config, with a default** — a new knob lives on `DocsKit::Configuration` with a sensible default so existing sites keep working (backwards compatible)
3. **Compose from the kit** — new chrome is a `DocsUI::` component, not markup
4. **Render through a real view context** — `#render_page` renders with `layout: false` because `DocsUI::Shell` IS the whole document; CSRF, `dom_id`, url helpers, and (on reactive sites) the token signer must still work
5. **Keep the switcher and the CSS in sync** — themes offered == themes built
6. **Wire setup into the install path** — the generator templates and `docs-kit new` template, both
7. **Assert on semantics, not snapshots** — a component spec checks an active link / a present theme / a config-driven value, not a brittle full-HTML string

## The two things you'll be asked to do

### A. Change the gem (a component, config knob, generator, the engine)

Follow Critical Rules above. Read the load-bearing file for the layer you're
touching before writing code — see Architecture below for the layer map.

### B. Write a docs page for docs-kit's own docs site (under `docs/`)

The dogfood site is itself a docs-kit site. Its registry is
`docs/app/models/doc.rb`; its pages are `docs/app/views/docs/pages/`. To
document a feature of the gem:

**1. Scaffold** (from the `docs/` app):

```bash
cd docs && bin/rails g docs_kit:page "Getting Started" --group=Guide
```

That writes `docs/app/views/docs/pages/getting_started.rb` **and** injects
the required `page "Getting Started", group: "Guide"` line into `Doc`.
Overrides: `--slug`, `--view`, `--eyebrow`, `--registry`. The registry line is
**required** — no line, no page.

**2. Write `#content` — Markdown first.** Prose is `md` with a
**single-quoted** heredoc (`<<~'MD'`) so `#{…}` stays literal (Phlex escapes
author text — never `html_safe` or interpolate). `DocsUI::Section` owns page
structure and the TOC; never use a Markdown `##` for structure. The primary
arg is positional, modifiers are keywords: `Section("Title", description:)`,
`Code(source, filename:)`. For no positional arg use the lowercase helpers
`md` / `prose` / `example`. Reference material has dedicated helpers:
`DocsUI::PropTable`, `DocsUI::FieldTable`, `DocsUI::RequestExample`,
`DocsUI::Callout(:note | :tip | :warning)`.

The always-current, worked example of the whole contract is
`docs/app/views/docs/pages/authoring.rb` (rendered at `/docs/authoring`).
Read it before writing a page.

## Commands

```bash
bundle exec rspec        # Suite (component render + registry + config + generator); SimpleCov enforces an 80% minimum
bundle exec rubocop      # Lint (rubocop -A to autocorrect)
bundle exec rake         # spec + rubocop, together — mixes both tools' raw output, so prefer running the two commands above separately when you need to read the result
bun run build:css        # Rebuild the Tailwind/daisyUI CSS (in the docs/ app, or a consuming site)
```

Command output is condensed by rtk (PreToolUse hook). Write commands in
hook-rewritable shapes: no `for`/subshell wrappers, no `| head` on
rtk-handled commands, `bundle exec rubocop` not `bin/rubocop`.

Never `gem push` by hand — release via `rake release[X.Y.Z]`.

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
> **configuration**, not markup. A component reads `DocsKit.configuration`;
> the server renders a working page; the one `docs-nav` controller enhances
> it.

Client interactivity is client-only UX polish (which `<details>` you left
open, the "on this page" TOC) — there is no server round-trip. See
`README.md`.

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
naming invariant: `image`/`service` must be the calling repo's `OWNER/REPO`
so `GITHUB_TOKEN` can push (build) and pull (deploy) the auto-linked GHCR
package. See the README "Deploy a new docs site" section for the five wiring
points and the naming note.

## Screenshots on PRs and issues (always)

`gh` ≥ 2.99 uploads images and videos itself. A change to `DocsUI::` chrome
(Shell, Sidebar, ThemeSwitcher, Page, Callout, …) or to a docs page's rendered
output ships with before/after pictures **on the PR**, attached from the
terminal. Never a local path, a base64 blob, or "screenshot available on
request".

```bash
gh pr create --attach './after.png#Sidebar collapsed on mobile' --title … --body …   # picture in hand already
gh pr comment <n> --attach './after.png#Sidebar collapsed on mobile' --body 'Before/after for the sidebar.'
gh pr comment <n> --attach ./before.png --attach ./after.png   # repeat the flag, up to 50 files
gh issue comment <n> --attach ./repro.mp4                       # video renders as a player
```

- Quote the whole argument: the alt text has spaces and bare `<`/`>` would
  redirect. `<file>#<alt text>` sets the alt text; without it the filename is
  used. A body that already references the file (`![alt](./after.png)`) gets
  that reference rewritten to the uploaded asset, so images can sit inline;
  unreferenced attachments are appended at the end.
- `create`, `edit` and `comment` all take `--attach` (all three landed in gh
  2.99). Attach at create time when the picture already exists; comment when
  it comes later, as it does after a verification run.
- Capture with `agent-browser screenshot <file>` or the Playwright MCP
  `browser_take_screenshot`, pointed at the `docs/` dogfood app (`bin/dev`) or
  a consuming site. Save under the scratchpad, never in the repo.
- No `--attach` flag means an old `gh`: `brew upgrade gh`.

## Claude Code specifics

Slash commands (`.claude/commands/`) and rules (`.claude/rules/`) drive
autonomous work: `/plan`, `/lfg`, `/tdd`, `/architect`, `/security`,
`/review-pr`, `/github-review-pr`, `/github-review-failures`,
`/github-review-comments`. Full purpose + model tier per command, and the
model-tier convention (`haiku`/`sonnet`/`opus`/`fable`) for subagents:
`.claude/README.md`.

## More Documentation

- `.claude/commands/` — slash command definitions
- `.claude/rules/` — coding style, git workflow, testing, agents
- `.claude/README.md` — command index + model tiers
- `README.md` — the full install/configure/render/deploy guide
