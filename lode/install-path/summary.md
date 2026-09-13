# Install path — generators, templates, the CLI

Three entry points get a site running: `rails g docs_kit:install` (wire an app), `rails g docs_kit:page` (add a page), and `docs-kit new NAME` (scaffold a whole app). The rule underneath all three: a required setup step lands in the **install generator and the `docs-kit new` template**, never in the README alone.

## `InstallGenerator` — `rails g docs_kit:install [--sync]`

`lib/generators/docs_kit/install/install_generator.rb`, 622 lines, 20 public Thor steps that run in declaration order, then private helpers from line 379. 16 templates live beside it.

Fully idempotent by design, which is what makes re-running it the sanctioned upgrade path. `--sync` narrows it to the additive wiring: `create_registry_and_pages` and `create_css_build` return early with a skip status (`install_generator.rb:130`, `186`), and `run_migrations` runs **only** under `--sync` (`332-340`).

Three ownership categories decide what a step does:

| Category | Behaviour | Examples |
|---|---|---|
| Site-owned | skip when present; print the template path for a manual diff | `config/initializers/docs_kit.rb` (`104-112`), `Dockerfile` (`211-219`), the skill file (`439-444`), the phlex and rails_icons initializers |
| Gem-owned wiring | refreshed on every run | `lib/tasks/docs_kit_og.rake` (`201-203`), `.dockerignore` (`225-227`, `force: true`) |
| Merged | read, merge, write back only if changed | `.rubocop.yml` (`450-464`), `AGENTS.md` (`429-435`) |

Steps worth knowing:

- **`add_routes`** (`139-159`). `route_once` guards on the endpoint, not on Thor's byte-identical skip. Thor's `route` **prepends**, so the search route is drawn *after* the `docs/:doc` route in order to land *above* it in the file — otherwise `docs/:doc` swallows `/docs/search`. The docs route carries `(.:format)` and deliberately no `defaults: { format: "html" }`, because that would pin html and defeat the `.md` twin.
- **`add_mcp_route`** (`172-180`). Drawn **commented out** — MCP needs the optional `mcp` gem. Guarded on `route_present?`, not Thor's skip: a site that opted in has live routes in its own style that never byte-match the commented template, so plain `route` would re-inject the scaffold on every `--sync` (found dogfooding 1.0.3 into pgbus and phlex-reactive).
- **`register_stimulus_controller`** (`287-310`). Skips when either loader already registers `docs_kit/controllers`, in any quote style. If there is no eager anchor to inject after, it appends **only** when the file already imports `eagerLoadControllersFrom`; a lazy-only index is valid, and appending an unimported eager call would throw a `ReferenceError` that registers zero controllers, so it warns instead.
- **`create_thrust_binstub`** (`235-246`) and **`gemfile_bundles_thruster?`** (`604-619`). The Dockerfile's exec-form `CMD ["./bin/thrust", …]` needs the file to exist in the image, and `bundle install` installs the gem, not app binstubs — without this the image builds green and the container crashes at boot. The Gemfile scan does line-level block tracking (`… do` pushes, `end` pops) and counts a `gem "thruster"` line only outside every `group` block and without an inline `group:` kwarg, because the Dockerfile sets `BUNDLE_WITHOUT="development:test"`.
- **`stamp_synced_version`** (`348-359`) writes the inert `# docs-kit synced: vX.Y.Z` comment at the top of the initializer — the one file every site has, and the one `create_initializer` never rewrites, which is why stamping is its own step. It updates a stale stamp in place and is a no-op when current. `#synced_version` (`385-390`) reads it **before** the restamp; an unstamped site reads `"0.0.0"`, so every migration applies.

`#app_brand`, `#docker_service` and `#ruby_version_arg` are the template bindings (the app name humanized, the app dir basename, and the host's running Ruby).

## `SyncReport` — drift detection

`lib/generators/docs_kit/install/sync_report.rb`, 90 lines, three checks: `ApplicationController` defining its own `render_page` (`49-55`), a leftover `app/helpers/icon_helper.rb` (`59-64`), and a `Dockerfile` whose `# docs-kit Dockerfile vX.Y.Z` marker is older than `DocsKit::VERSION` (`70-80`). String-level and conservative: it reads, reports, and **never touches a byte**. A Dockerfile with no marker is one the site brought itself and is left alone — no stamp, no warning. `report_drift` runs on every invocation, not just `--sync`, and never fails the run.

## `Migration` / `MigrationRegistry` — versioned upgrades

`MigrationRegistry.default.migrate!(synced_version, root, generator)` selects migrations in the half-open range `(from_version, upto]` — above the site's stamp, no newer than the installed gem — and runs them ascending, collecting warn-only messages. The `upto` ceiling exists because `--sync` restamps to `DocsKit::VERSION` afterward: a migration targeting an unreleased version would exceed every future stamp and re-run forever.

`MIGRATIONS` is `[].freeze`. The registry ships **empty**; the mechanism is the deliverable, and the first concrete transform is a one-line `Migration.new(to: …)` addition. A migration is warn-only-safe by contract: it does what it can idempotently and hands back strings for whatever needs a human.

## `PageGenerator` — `rails g docs_kit:page TITLE --group=GROUP`

Writes `app/views/docs/pages/<view>.rb` **and** injects the one-line `page` entry into the registry. `--slug`, `--view`, `--eyebrow`, `--registry` override every derivation; `#override_kwargs` (`page_generator.rb:91-96`) spells out `slug:`/`view:` only when they differ from the derived defaults.

Two guards. A legacy `entries [...]` registry is detected (`#legacy_entries?`, `100-102`) and left alone with a by-hand instruction printed, rather than corrupted by a `page` line. And `#registry_anchor` (`113-124`) returns the last `page` line as a **String**, not a Regexp: Thor's `inject_into_file` replaces *every* match of a Regexp `after:`, so a "page line not followed by a page line" pattern fires once per group in the blank-line-separated layout the install generator produces, duplicating the entry. Falls back to `view_namespace`, then `path_prefix`, then the `extend DocsKit::Registry` line.

## `exe/docs-kit` and `templates/new_site.rb`

`docs-kit new NAME [--image OWNER/REPO] [--service NAME] [--gem-source SRC]` runs `rails new` with propshaft + importmap + turbo + stimulus (deliberately **not** `--minimal`, which strips JS entirely) and applies `lib/docs_kit/templates/new_site.rb`.

The CLI resolves the environment **before** the template runs (`exe/docs-kit:59-63`): `DOCS_KIT_IMAGE` defaults to `zoolutions/#{name}` and `DOCS_KIT_SERVICE` to `name`. The template's `ENV.fetch` fallbacks (`new_site.rb:26-27`) are therefore only reachable when the template is applied directly, not through the CLI — so the CLI default, its two help-text mentions, and the template fallback must be changed together.

The naming invariant: `image` must be the calling repo's `OWNER/REPO` so the auto-linked GHCR package lets `GITHUB_TOKEN` both push and pull it. A name that doesn't match becomes an unlinked user-scoped package `GITHUB_TOKEN` can't pull. `service` must equal `service:` in `config/deploy.yml` and is stamped as the image's `service` LABEL; the template corrects the Dockerfile's LABEL when `--service` differs from the app name.

## The CSS contract

`bin/build-css` (shipped as a template) resolves the `daisyui` and `docs-kit` gem paths with `bundle show` and writes `@source` globs into `app/assets/stylesheets/tailwind.sources.css`, which `application.tailwind.css` imports. It aborts when a gem can't be resolved — a silently missing `@source` ships an unstyled site. The generated file is per-environment; the sites that have it gitignore it (`docs/.gitignore:38`).

## Shipped RuboCop cops

`lib/rubocop/cop/docs_kit/` holds two cops, loaded by `require "docs_kit/rubocop"` (which requires rubocop lazily — it is a host dev-time dependency, never a docs-kit runtime one) and enabled by `inherit_gem: { docs-kit: config/rubocop/docs_kit.yml }`. Both default to `Include: app/views/docs/**/*`.

- `DocsKit/RenderComponentPreferred` — prefer `DocsUI::Code(…)` over `render DocsUI::Code.new(…)`. It keeps the namespace prefix, because an unqualified helper may resolve to a different kit depending on inclusion order.
- `DocsKit/EscapedInterpolationInHeredoc` — use a single-quoted heredoc delimiter instead of escaping `\#{…}`. It treats all three Ruby interpolation sigils (`#{`, `#@`, `#$`) as the escape tax, and a live unescaped occurrence of any of them blocks autocorrection.

`wire_rubocop_cops` (`275-285`) writes `RUBOCOP_STARTER` when the site has no `.rubocop.yml`, and otherwise merges — a `rails new` app ships an omakase `inherit_gem` that must not be dropped.

## Related

- `../components/summary.md` — why `eagerLoadControllersFrom` is the only safe register line
- `../testing-and-ci/summary.md` — the generator specs and the deploy workflows
