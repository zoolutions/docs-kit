# Core — loader, engine, controller glue, request scope

The four files that decide what loads, what Rails hooks are installed, and what a request sees.

## `lib/docs_kit.rb` — the loader

Requires `phlex`, `rouge`, `zeitwerk`, then `docs_kit/version` and `docs_kit/configuration` eagerly. `DocsUI` is declared and `extend Phlex::Kit` **before** `loader.setup`, so zeitwerk autoloads its children into an already-extended module — reorder that and the kit helper methods stop being defined.

Two `push_dir` calls: `lib/docs_kit/` → `DocsKit`, and `app/components/docs_ui/` → `DocsUI`. Nine `loader.ignore` calls follow, each for its own reason:

| Ignored | Why |
|---|---|
| `version.rb`, `configuration.rb` | required eagerly above; zeitwerk would double-manage the constants |
| `seo_config.rb`, `landing_config.rb` | required eagerly by `configuration.rb` |
| `brand_logo.rb` | required eagerly by `landing_config.rb` (the `LandingConfig::Logo` alias resolves at require time) |
| `og_generator.rb` | loaded only by the host's `docs_kit:og` rake task, so its browser tooling never reaches a host that doesn't run it |
| `rubocop.rb` | defines `RuboCop::Cop::DocsKit::*`, not a `DocsKit::Rubocop` constant |
| `engine.rb` | required explicitly below, only under Rails |
| `templates/` | a Rails application template, not autoloadable Ruby |

The last line is `require_relative "docs_kit/engine" if defined?(Rails::Engine)`. `lib/docs-kit.rb` exists only because Bundler auto-requires the file matching the gem name; it delegates to `docs_kit.rb`.

## `lib/docs_kit/engine.rb` — glue only

An asset/glue engine: no `isolate_namespace`, no routes, no models. It sets `config.autoload_paths = []`, `config.eager_load_paths = []` and `paths["app"].skip_eager_load!` so Rails does not also autoload `app/components` — the gem's own zeitwerk loader is the single owner of those constants.

Four initializers: include `DocsKit::Controller` into `ActionController::Base`; register `text/markdown` as `:md` (guarded, so a host that already declared it is a no-op); append `app/javascript` to the asset paths; and, `before: "importmap"`, append `config/importmap.rb` to `importmap.paths` and the JS dir to `importmap.cache_sweepers`. That last one is what auto-pins `docs_kit/controllers/docs_nav_controller`; each of the three appends is guarded by a `respond_to?` so a host without importmap-rails or without the assets config still boots.

The engine draws **no routes**. `LlmsController`, `SearchController` and `McpController` are gem controllers the host wires itself, which is what leaves a site in control of path, auth and omission — and why the install generator's `add_routes` exists.

## `lib/docs_kit/controller.rb` — `#render_page`

56 lines, three methods. `#render_page` (`controller.rb:29-35`) wraps the whole render in `DocsKit::Scope.with(version: config.resolve_version(params[:version]))`, then either returns the Markdown twin or `render view, layout: false`. `layout: false` is not optional: `DocsUI::Shell` emits `<html>`/`<head>`/`<body>` itself, so the Rails ERB layout would double-nest the document. phlex-rails still renders through a real view context, so CSRF, `dom_id`, url helpers and a reactive site's token signer work inside components.

`#markdown_request?` (`controller.rb:42-44`) accepts `.md` **or** `.text` — `.text` is the alias for a host whose routes only permit the built-in format. `#render_markdown` builds a `DocsKit::MarkdownExport` with the controller's `view_context` and `request.base_url` and renders it as `text/markdown`.

The block wrapper is sufficient because `render` runs synchronously inside the action — no `around_action`, no host code change.

## `lib/docs_kit/scope.rb` and `scoping.rb` — the request axis

`Scope` is a `module_function` module over `Thread.current[:docs_kit_scope]` (fiber-local in Ruby, which is what a fibered server wants) — deliberately **not** `ActiveSupport::CurrentAttributes`, so a bare Phlex component spec can set a scope without booting Rails. `Scope.with` restores the previous scope in an `ensure`, so a raising block cannot leak a version across requests sharing a thread. An empty scope reads as `version: nil` / `locale: nil`, which every consumer treats as "the current version" — today's behaviour on an unversioned site. `Scope.locale` is reserved for a future i18n axis and is nil in every path today.

`Scoping` is a plain module with an `included` hook (not an `ActiveSupport::Concern` — it has no dependency chain and must stay loadable Rails-free) that installs `around_action :docs_scope`. The gem's three controllers include it. A host's own docs controller does **not**: it gets the same behaviour from `render_page`'s wrapper, because `around_action`-ing every host action is not the gem's call to make.

## Related

- `../config/summary.md` — what `resolve_version` reads from
- `../registry-and-versions/summary.md` — `DocVersion`, `Snapshot`, and what an archived scope swaps
- `../ai-surfaces/summary.md` — the three gem controllers that include `Scoping`
