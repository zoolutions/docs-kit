# docs-kit

A Rails engine gem (`docs-kit`, `DocsKit::VERSION` 1.1.1) that ships the shared Phlex/daisyUI chrome for documentation sites — the shell, sidebar, code blocks, theme switcher and page kit — plus the AI surfaces a docs site is expected to have (a Markdown twin of every page, `/llms.txt`, server-rendered search, an optional MCP endpoint) and the install path that wires a site up (`rails g docs_kit:install`, `rails g docs_kit:page`, the `docs-kit new` CLI, a reusable deploy workflow). Several sites — importmap-plus, phlex-reactive, glyphs, and this repo's own `docs/` dogfood app — run the same chrome and differ only in their `DocsKit.configure` block.

Three invariants govern every change.

**Chrome is configuration, not markup.** A `DocsUI::` component reads `DocsKit.configuration`; nothing site-specific is hardcoded in a component, and a site never hand-writes drawer or menu HTML. The 36 top-level knobs on `DocsKit::Configuration` (plus the nested `c.seo.*` and `c.landing.*` blocks) are the whole surface a site tunes.

**The server renders a working page.** There is exactly one Stimulus controller, `docs-nav`, auto-pinned by the engine (`config/importmap.rb`), and it only *enhances* — collapse persistence, the auto-TOC, scroll-spy, the search palette. With JavaScript off the sidebar renders fully expanded and the search form still submits.

**A new knob defaults backwards-compatibly.** Every opt-in feature reads as absent when unset, so a site that upgrades and changes nothing renders byte-identical markup. `c.versions = []`, `c.topbar_links = []`, `c.brand_logo = nil`, `c.openapi = nil`, `c.seo.og_image = nil` are all the same shape: absent value, absent tag.

The gem is deliberately loose on Rails. The gemspec declares no `rails`/`railties` dependency; `lib/docs_kit.rb` requires the engine only `if defined?(Rails::Engine)`, and the suite renders the components with no Rails boot. The Rails-only bits — `Rails.root`, `Rails.env` — are each guarded by a `defined?(Rails)` check.
