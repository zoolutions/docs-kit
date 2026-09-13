# Testing, CI, deploy, and the dogfood site

## The suite

RSpec, 62 spec files, 953 examples (`bundle exec rspec --dry-run`). `.rspec` is `--require spec_helper --format documentation`.

| Layer | Path | Files | Boots |
|---|---|---|---|
| Unit | `spec/docs_kit/**` | 27 | nothing — config, registry, scope, snapshot, the value objects, `LlmsText`, `SearchIndex`, `McpTools`, the OpenAPI model, the three gem controllers |
| Component | `spec/docs_ui/**` | 28 | a Phlex render, no Rails request |
| Generator | `spec/generators/**` | 4 | plain Thor against a tmp app skeleton — install, page, migration, migration_registry |
| Cops | `spec/rubocop/**` | 2 | RuboCop's cop harness |

Plus `spec/docs_kit_spec.rb` for the module itself. Fixtures: `spec/fixtures/openapi.{json,yaml}` and `spec/fixtures/snapshots/1.0/` (a manifest plus two `.md` pages).

`spec/spec_helper.rb` starts SimpleCov **before** requiring `docs_kit` (line 7) with `minimum_coverage 80` and branch coverage, so `rspec` and `rake` fail below the floor locally and in CI. It then loads just enough to render the chrome standalone: two ActiveSupport core-exts, `phlex/rails`, and `daisy_ui` — the gem never requires daisyui itself, the host does, so the constant would otherwise be undefined when a component renders. `mcp` is required in a `begin/rescue LoadError`. `config.order = :random`, monkey-patching disabled, and a `before` hook calling `DocsKit.reset_configuration!` so every example starts clean.

The rules in `../../.claude/rules/testing.md`: assert on semantics (an active link, a present theme option, a config-driven value), not full-HTML snapshots; 100% aspired for `Configuration` and `Registry`.

## CI — `.github/workflows/ci.yml`

Triggers on push to `main` and every pull request, with `cancel-in-progress` concurrency per ref. Three jobs:

1. **`rake`** — `bundle exec rake` (spec + rubocop) on Ruby 3.2, 3.3, 3.4, `fail-fast: false`.
2. **`docs-site`** — the dogfood app's own RSpec: request specs plus Playwright/chromium system specs. It sets `BUNDLE_FROZEN: "false"` because the app depends on the gem via `path: ".."` and the gemspec lists files with `git ls-files`, so **every commit changes the path-gem's digest** and bundler's frozen mode (forced by `bundler-cache`) fails with "the gemspecs for path gems changed". This job is the only coverage that a logical `og_image` resolves to a served, digested `/assets` URL — the exact gap that let the og:image 404 ship.
3. **`without-mcp`** — installs with `bundle config set --local without mcp` and runs the suite, proving the optional MCP feature no-ops when the gem is absent.

`Rakefile`'s RuboCop task passes explicit patterns (`app lib spec Rakefile Gemfile docs-kit.gemspec`) so RuboCop never discovers `docs/.rubocop.yml`, whose `inherit_gem` can't resolve in the gem's bundle. `docs/` lints itself.

## Release

`rake release[X.Y.Z]` (`Rakefile:40-171`), never `gem push`. It aborts unless the branch is `main` and the tree is clean, bumps `lib/docs_kit/version.rb`, refreshes both lockfiles and runs `gem build --strict` as verification, commits **only** `version.rb`, pushes `main`, and creates the GitHub Release. The root `Gemfile.lock` is gitignored so its refresh is pure verification; `docs/Gemfile.lock` is **tracked**, so the release leaves it modified and uncommitted and someone lands the new pin in a follow-up commit (`97a696a`, "chore(docs): refresh docs lock for 1.1.0"). Between the two, the tracked pin lags `DocsKit::VERSION`. `release.yml` then publishes to RubyGems over OIDC trusted publishing. `rake release[pre]` re-releases the current version as a prerelease; a second `force` argument deletes the existing release and tag first.

Because releases land directly on `main`, a feature branch never edits `version.rb` — a conflict there means the branch is a deliberate release-prep PR.

## Deploy

`deploy.yml` is the **reusable** workflow every docs-kit site calls, so the build+deploy is defined once: buildx build with registry cache, push to GHCR, then `dash` deploys with `--skip-push` so the image is never built twice. `deploy-docs.yml` is this repo's thin caller (`image: zoolutions/docs-kit`, `service: docs-kit`) firing on `release: published` and `workflow_dispatch`.

Two things bite callers. The caller must **grant** `packages: write` — a reusable workflow can only narrow the permissions it is given, so with the repo default of read-only the build job's `packages: write` exceeds the grant and the run is a `startup_failure`. And the `secrets:` inputs are declared `required: false` on purpose: callers pass them with `secrets: inherit`, and GitHub cannot statically confirm an inherited secret satisfies `required: true`, which is itself a `startup_failure`. They are still effectively required — the deploy step fails fast on an empty `DEPLOY_HOST`/`DEPLOY_DOMAIN`.

The build job checks out with `persist-credentials: false`: the image `COPY`s the repo root including `.git` (kept for the gemspec's `git ls-files`) and is pushed to a public GHCR package, so a persisted `GITHUB_TOKEN` in `.git/config` must not ride along into a published layer.

## The dogfood site — `docs/`

A real Rails app under `docs/`, depending on the gem via `path: ".."`, deployed to https://docs-kit.zoolutions.llc. It is a docs-kit site like any other: `docs/app/models/doc.rb` is the registry (14 `page` lines across five groups), `docs/app/views/docs/pages/` holds the page classes.

Its own bundle, `.rubocop.yml`, `.rspec` and specs — run everything from inside `docs/`, never the repo root. `docs/bin/ci` (via `docs/config/ci.rb`) chains setup, RuboCop, bundler-audit, `bin/importmap audit`, Brakeman, and `bin/rspec`. `docs/Gemfile.lock` and `docs/bun.lock` are **tracked** (a deployable app commits them) while the gem root's `Gemfile.lock` is gitignored.

Adding a page: `cd docs && bin/rails g docs_kit:page "Title" --group=…`. The authoring contract is `../../AGENTS.md` and the always-current worked example is `docs/app/views/docs/pages/authoring.rb`, rendered at `/docs/authoring`.

## Related

- `../install-path/summary.md` — what the generator specs exercise
- `../../.claude/rules/testing.md` — the layer table and coverage bars
