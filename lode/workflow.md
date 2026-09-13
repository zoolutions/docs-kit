# Workflow profile

Everything the shared workflow skills (`/lode:lfg`, `/lode:review-pr`,
`/lode:finish-prs`, `/lode:debug-flaky`, `/lode:tdd`, `/lode:plan`) need to know
about docs-kit that is not already in `../CLAUDE.md`, `../AGENTS.md`,
`../.claude/rules/` or the rest of `lode/`.

## Commands

| Purpose | Command | Notes |
|---|---|---|
| fast loop (one file) | `bundle exec rspec spec/<path>_spec.rb` | the examples run and report, but the **process still exits non-zero**: SimpleCov's `minimum_coverage 80` (`spec/spec_helper.rb:15`) measures the whole of `lib/` and `app/` on every run, and one file never reaches 80%. Read the `N examples, M failures` line, not the exit code. There is no env escape hatch. |
| full suite | `bundle exec rake` (= `spec` + `rubocop`; `Rakefile:173`) | 62 spec files, 953 examples. No network, no services, no browser — the gem suite renders Phlex standalone. Safe to run in two worktrees at once. |
| lint | `bundle exec rubocop` (1.91.0) | `rake rubocop:autocorrect` for the safe cops. The task passes explicit patterns (`app lib spec Rakefile Gemfile docs-kit.gemspec`, `Rakefile:14`) so RuboCop never discovers `docs/.rubocop.yml`, whose `inherit_gem` cannot resolve in the gem's bundle. |
| one CI cell locally | `bundle exec rake` for the `rake` job; `cd docs && bundle exec rspec` for `docs-site` (needs a Playwright chromium: `cd docs && bunx --bun playwright install chromium`); `bundle config set --local without mcp && bundle install && bundle exec rspec` for `without-mcp` — **unset it afterwards** (`bundle config unset --local without`) or every later run hides the MCP specs | |
| docs build / check | `cd docs && bin/ci` (setup → rubocop → bundler-audit → `bin/importmap audit` → brakeman → rspec). `cd docs && bun run build:css` rebuilds the Tailwind/daisyUI CSS | always from inside `docs/` — it is a separate app with its own bundle, `.rubocop.yml`, `.rspec` and lockfiles. There is no `package.json` at the repo root. |
| run the app | `cd docs && bin/dev` (`bin/rails server`) | the dogfood site is the only runnable app in the repo |
| the scaffolder | `ruby exe/docs-kit --help` | `docs-kit new NAME [--image OWNER/REPO] [--service NAME] [--gem-source SRC]`; it shells out to `rails new`, so only run it for real in a throwaway directory |

## Branches and PRs

- Default branch: `main`. All work goes through a PR; never commit to `main` directly.
- Work branches: `feature/*`, `fix/*`, `refactor/*`, `ci/*`, `chore/*`, rooted off fresh `origin/main` (`../.claude/rules/git-workflow.md`).
- Commits: conventional, with a scope drawn from the architecture — `shell`, `sidebar`, `code`, `page`, `theme`, `registry`, `controller`, `generator`, `engine`, `deploy`, `docs`, `ci`. The body says **why**.
- A `gh pr`/`gh issue` body written through a single-quoted heredoc is copied verbatim: never escape backticks or pipes.
- PR body sections, in order: Summary, Test plan, Deviations & judgment calls, Gate.
- Merge policy: squash on `main` once CI is green and the PR is approved. Never rebase a branch that has a PR — merge `main` forward into it.
- Attribution: no `Co-Authored-By: Claude`, no "Generated with" line. End a commit body with `Claude-Session: <url>` and a PR body with the session URL.

## Layers

| Layer | Files | Edit rule |
|---|---|---|
| Client runtime | `app/javascript/docs_kit/controllers/docs_nav_controller.js` (the only one) | owned here — but it may only *enhance*. Never add a second controller; never make a page require it. |
| Components | `app/components/docs_ui/*.rb` (30 classes + `page_helpers.rb`) | owned here. New chrome is a `DocsUI::` component, never raw daisyUI markup, and it reads `DocsKit.configuration` rather than hardcoding. |
| AI surfaces | `lib/docs_kit/{markdown_export,blocks,inline,table,llms_text,search_index,search_hit,mcp_tools,mcp_server,open_api}.rb`, `app/controllers/docs_kit/*.rb` | owned here. A new consumer calls `LlmsText.pages` / `.renderable_for`; it does not re-derive the page list. |
| Registry + versions | `lib/docs_kit/{registry,doc_version,snapshot,nav_item}.rb` | owned here. `Registry`'s public API is what sites depend on — additive only. |
| Config | `lib/docs_kit/configuration.rb` plus the value objects | owned here. A new knob ships with a default that renders nothing. |
| Core | `lib/docs_kit.rb`, `engine.rb`, `controller.rb`, `scope.rb`, `scoping.rb` | owned here. The `DocsUI`/`Phlex::Kit` extend must stay before `loader.setup`; a new file needs the matching `loader.ignore` reasoning. |
| Install path | `lib/generators/docs_kit/**`, `lib/docs_kit/templates/new_site.rb`, `exe/docs-kit` | owned here. Every step must be a genuine no-op on re-run, proved by a spec that runs it twice. |
| Generator templates | `lib/generators/docs_kit/install/templates/**` (16 files) | owned here, but they become **site-owned** once written: the generator skips them, so a change only reaches existing sites through a `Migration`. |
| Shipped cops | `lib/rubocop/cop/docs_kit/*.rb`, `config/rubocop/docs_kit.yml` | owned here; rubocop is a host dev-time dependency, required lazily. |
| Dogfood site | `docs/**` | a consuming app, not gem source. Its own bundle and lint; the gem's `rake rubocop` deliberately excludes it. |
| Vendored icons | `docs/app/assets/svg/icons/**` | vendored Lucide copies — re-vendor, never hand-edit. |
| Lockfiles | `docs/Gemfile.lock`, `docs/bun.lock` (tracked); root `Gemfile.lock` (gitignored) | generated — regenerate, never hand-edit. |

## Shapes

Check a change against every one of these before calling it done.

- **A site that sets nothing.** Every opt-in knob must render byte-identical markup when unset (`c.versions = []`, `c.topbar_links = []`, `c.brand_logo = nil`, `c.openapi = nil`, `c.seo.og_image = nil`).
- **A render with no Rails.** Component specs render Phlex standalone; `MetaTags` may render in a static build. Anything touching `view_context`, `request` or `Rails.*` guards or rescues first.
- **JavaScript off.** The server-rendered page is fully expanded, the search form submits, the theme is the configured default.
- **Both registry styles.** The `page` DSL and the legacy `entries [...]` API — and an `entries` registry whose instances define no `#view_class` contributes no nav items at all.
- **A declared-but-unwritten page.** `Registry::Entry#view_class` is nil until the class exists; `nav_items` and `LlmsText.pages` both filter on it.
- **An archived version in `DocsKit::Scope`.** `Configuration#nav_groups` and `LlmsText.pages` branch on it; a missing or unparseable snapshot must read back empty, not raise.
- **An unknown `params[:version]`.** `resolve_version` degrades to the current version; it never 404s.
- **The `mcp` gem absent** (a whole CI job), and `rails_icons` absent.
- **A site re-running the generator.** `--sync` and a full run; an unstamped site (`synced_version` reads `"0.0.0"`); a site that already wrote the route or the Stimulus register line in its own quote style; a `.rubocop.yml` that already has an omakase `inherit_gem`.
- **Ruby 3.2** — the gemspec floor and the oldest CI cell.
- **Request formats** `.md` and `.text`, not just `html`.
- **A relative and an absolute `og_image`**, and none at all.
- **A dark theme that is not in `config.themes`** — `dark_themes_shipped` must emit no dead CSS.
- **A Tailwind class that no source line spells literally** — it is tree-shaken out unless a site adds `@source inline(...)`.

## Constraints

Reviewer suggestions that are wrong in this repository. Push back on sight.

| Suggestion | Why it is wrong here |
|---|---|
| "Add `rails`/`railties` to the gemspec" | Deliberate: `docs-kit.gemspec` declares none, `lib/docs_kit.rb` requires the engine only `if defined?(Rails::Engine)`, and the whole suite renders Rails-free. |
| "Make `mcp` a real dependency" | It is runtime-detected (`Configuration#mcp_gem_present?`) and the `without-mcp` CI job exists to prove the feature no-ops without it. |
| "Use `ActiveSupport::CurrentAttributes` instead of `Thread.current` in `Scope`" | A bare Phlex component spec must be able to set a scope without booting Rails. |
| "Name the controller's config reader `#config`" | `ActionController::Base#config` is Rails' config object and `RequestForgeryProtection` delegates to it; shadowing it breaks `csrf_meta_tags`. All three gem controllers use `#docs_config`. |
| "Extract these Tailwind classes into an interpolated helper" | Tailwind scans the Ruby source; an interpolated class name is tree-shaken out of the build. Class lists stay literal strings. |
| "Use `render json:` in `McpController`" | `server.handle_json` already returns a serialised JSON string; `render json:` re-encodes it and corrupts the JSON-RPC envelope. |
| "Let Thor's `route`/`template` skip handle idempotence" | Thor skips only a **byte-identical** line, which is useless against a site that wrote the same route in its own style. Detection is semantic (`route_present?`, `stimulus_registered?`). |
| "Use a Regexp `after:` for `inject_into_file`" | Thor replaces *every* Regexp match; `PageGenerator#registry_anchor` returns a String for exactly this reason. |
| "Use `lazyLoadControllersFrom`" | The default `controllers/index.js` imports only the eager loader, so a lazy call throws a `ReferenceError` that aborts the module and registers **zero** controllers. |
| "`raw`/`html_safe` this config value" | Only gem-authored or shape-checked markup may bypass Phlex escaping (seven call sites). Config free text flows through `plain` or an ordinary attribute. |
| "Bump `lib/docs_kit/version.rb` in this PR" | Releases land directly on `main` via `rake release[X.Y.Z]`, which aborts off `main`. A feature branch touching `version.rb` is either a deliberate release-prep PR or a mistake. |
| "Lint `docs/` from the root Rakefile" | `docs/.rubocop.yml` inherits gems absent from the gem's bundle; it lints itself. |
| "Rebase this branch onto `main`" | It has a PR, so it is shared — merge `main` forward instead. |
| "Document it in the README" (alone) | A required setup step lands in the install generator **and** the `docs-kit new` template, or new sites never get it. |

## Docs

- User-facing docs live in **two** places and both are user-facing: `README.md` (the full install/configure/render/deploy guide, 19 `##` sections) and the dogfood site's pages in `docs/app/views/docs/pages/` (14 pages, registered in `docs/app/models/doc.rb`).
- A change maps to a page by subject: a config knob → `configuration.rb`; a component → `components.rb`; authoring or Markdown → `authoring.rb` / `markdown.rb`; code highlighting → `languages.rb`; the AI surfaces → `ai.rb` and `search.rb`; the OpenAPI bridge → `open_api.rb` / `api.rb`; the install path → `installation.rb`; the CSS build → `styling.rb`; deploy → `deploy.rb`; the TOC → `on_this_page.rb`.
- Add a page with `cd docs && bin/rails g docs_kit:page "Title" --group=…`; the authoring contract is `../AGENTS.md` and the worked example is `docs/app/views/docs/pages/authoring.rb`.
- Changelog: `CHANGELOG.md`. New entries go under `## [Unreleased]`, in an `### Added` / `### Fixed` subhead (the two the changelog uses); a release renames the heading. Do not add a second subhead of the same name.
- Version-pinning files that drift after a release: **`docs/Gemfile.lock`** pins `docs-kit (X.Y.Z)` through `path: ".."`. `rake release` refreshes it but does not commit it, so it lags until someone lands `cd docs && bundle install` in a follow-up commit. `docs/bun.lock` drifts only when a JS dependency changes (`cd docs && bun install`).

## CI

- Workflows: `.github/workflows/ci.yml` (push to `main` + every PR, `cancel-in-progress` per ref); `release.yml` (RubyGems over OIDC trusted publishing, on a GitHub Release); `deploy.yml` (the **reusable** build+deploy every docs-kit site calls); `deploy-docs.yml` (this repo's thin caller, on `release: published` and `workflow_dispatch`).
- Three jobs, three different pictures of the same code:
  - `rake (Ruby 3.2 | 3.3 | 3.4)` — `bundle exec rake`, `fail-fast: false`. SimpleCov's 80% floor fails this job too.
  - `docs site (RSpec + Playwright)` — runs in `docs/` with `BUNDLE_FROZEN: "false"` (the path gem's digest changes on every commit, so frozen mode would fail), a real chromium, request + system specs. The only job that proves a logical `og_image` resolves to a served, digested `/assets` URL.
  - `gate (no mcp gem)` — installs `--without mcp` and runs the suite.
- Cells that differ from local: the `docs-site` job needs Playwright chromium installed and `RAILS_ENV=test`; the `without-mcp` job's bundle config is local-only and will silently persist if you reproduce it by hand.
- Fetch a failure: `gh pr checks <N>`, then `gh run view <RUN_ID> --job=<JOB_ID> --log-failed`.
- "Green" means all three jobs, every matrix cell.
- Known not-this-branch failures: a `Deploy docs` run failing on a missing `docs` environment secret or a dash image/service name is a deploy-wiring problem, not a code bug.
- Shared or rate-limited services the checks hit: none. Nothing in CI talks to a CDN or a registry beyond rubygems/npm during install, so PRs can run concurrently.

## Flake sources

- **Playwright/chromium system specs in `docs/`** — the only real browser in the repo, and the only place timing, animation and headless-rendering differences can bite. Everything in the gem suite is a synchronous Phlex render.
- **`config.order = :random`** with a `before` hook calling `DocsKit.reset_configuration!`. A spec that sets class-level or memoized state and does not reset it (`Snapshot.reset_cache!`, a `bundle config` left set, a `Scope` not unwound) fails only under some seeds. Reproduce with the printed `--seed`.
- **mtime-keyed memoization** (`Configuration#openapi_document`, `Snapshot.for`, `BrandLogo`'s `file:` form). A test that rewrites a fixture inside the same second can read the stale memo.
- **SimpleCov's coverage floor** is a whole-suite property: running a subset makes the process exit non-zero with every example passing. That is not a flake.
- Not a flake source: network calls. There are none in the gem suite.

## Conflicts

| File | Rule |
|---|---|
| `docs/Gemfile.lock` | never hand-merge: `git checkout --theirs docs/Gemfile.lock` (merging `origin/main` in makes the base "theirs"), `git add`, then `cd docs && bundle install` so the branch's own dependency changes re-resolve on top |
| `docs/bun.lock` | same: take the base's, then `cd docs && bun install`. CI installs with `--frozen-lockfile`, so a hand-edit fails there |
| root `Gemfile.lock` | gitignored — it can never conflict |
| `CHANGELOG.md` | union under `## [Unreleased]`: keep both sides' bullets, most recent first, without duplicating the `### Added` / `### Fixed` subheads |
| `lib/docs_kit/version.rb` | a feature branch never edits this; a conflict means the branch is a deliberate release-prep PR — keep the branch's bump. If the intent is not obvious from the branch's own commits, stop and ask |
| `docs/app/models/doc.rb`, `docs/config/routes.rb` | append-only registries: keep both sides' lines, base order first |
| `docs/app/assets/svg/icons/**` | vendored Lucide copies: take one side wholesale or re-vendor; never hand-merge SVG markup |
| `spec/fixtures/**` | add a second fixture rather than merge two shapes into one |

After resolving, run the gates the conflict touched — `bundle exec rake` at minimum, plus `cd docs && bundle exec rspec && bundle exec rubocop <changed docs files>` when `docs/` was involved — **before** pushing the merge commit.

## Verification

- The manual check a user of the change would do: `cd docs && bin/dev`, open `/docs`, and look at the page the change touches — with JavaScript disabled as well as enabled. For a Markdown-twin or AI-surface change, also fetch `/docs/<slug>.md`, `/llms.txt` and `/docs/search?q=…`. For a generator change, run `rails g docs_kit:install` twice against a throwaway app and diff — the second run must change nothing.
- A CSS-affecting change (a new emitted class) needs `cd docs && bun run build:css` and a look at the built output; a class no source line spells literally will be missing.
- Stress iterations for a flake proof: 50 runs of the suspect spec file with `--seed` varied (`for i in (seq 50); bundle exec rspec <file> --seed $i; end`); for an ordering-dependent failure, reproduce the exact `--seed` CI printed first.
- Where evidence goes: `lode/tmp/` (gitignored, never committed) unless the PR needs an auditable trail.
