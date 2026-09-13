# Practices

Patterns this codebase follows that `../.claude/rules/` does not already state. The rules cover style, testing layers, git flow and the SEO/OG contract; these are the shapes a reviewer will expect and a new contributor will otherwise re-invent.

## An opt-in knob reads as absent, never as broken

Every feature added since 1.0 defaults to a value that renders nothing: `c.versions = []`, `c.topbar_links = []`, `c.app_link = nil`, `c.brand_logo = nil`, `c.openapi = nil`, `c.code_theme_dark = nil`, `c.seo.og_image = nil` (`configuration.rb:295-337`). The component then guards on the reader and returns early — `Shell#app_home_link` (`shell.rb:197-207`), `Configuration#compare_url` (`configuration.rb:414-418`). "Absent value, absent tag" beats "absent value, empty tag", because an empty `og:image` or a bare `href=""` is a bug a reader sees and the suite does not.

## Degrade on the render path; raise at config time

A render must not take the site down for a config mistake that has a sensible fallback: an unresolvable Rouge theme name returns nil and falls back to the default (`Configuration#resolve_theme`, `configuration.rb:650-654`), an unreadable snapshot manifest reads back as an empty snapshot (`Snapshot#read_manifest`, `snapshot.rb:140-149`), an unreadable snapshot file renders as `""` (`Snapshot::Entry#markdown`), an unknown `params[:version]` resolves to the current version rather than 404ing (`Configuration#resolve_version`, `configuration.rb:391-393`).

The exceptions are deliberate and are all *configuration shape* errors, where there is nothing meaningful to degrade to: `c.topbar_brand` outside `TOPBAR_BRAND_MODES` raises `ArgumentError` at assignment (`configuration.rb:219`), `on_page` outside `ON_PAGE_MODES` raises in `coerce_on_page_mode` (`configuration.rb:535-543`), a malformed `c.brand_logo` raises on first read (`configuration.rb:352-356`), and `openapi_document` raises `DocsKit::Error` naming the knob when `c.openapi` is unset (`configuration.rb:443-451`). Loud at boot beats silently wrong in production.

## File-backed config memoizes and reloads on mtime

Three places read a file the developer edits while the server runs, and all three use the same shape — memoize, invalidate when the source's mtime changes: `Configuration#openapi_document` (`configuration.rb:443-451`), `Snapshot.for` (keyed on `[version id, root]`, `snapshot.rb:31-44`), and `BrandLogo`'s `file:` form. Copy that shape rather than a plain `||=`; a plain memo means a restart for every edit.

## A gem controller never defines `#config`

`ActionController::Base#config` is the Rails config object, and `RequestForgeryProtection` delegates `allow_forgery_protection` to it. Shadowing it breaks `csrf_meta_tags` the moment the controller renders a `<head>`. All three gem controllers name the reader `#docs_config` instead (`llms_controller.rb:63`, `search_controller.rb:50`, `mcp_controller.rb:62`). The same three declare their own forgery posture, because a bare `ActionController::Base` subclass does not inherit the host's `default_protect_from_forgery`: `:null_session` on the two GET-only text endpoints, `skip_forgery_protection` on the JSON-RPC MCP endpoint.

## Optional gems are runtime-detected, never gemspec dependencies

`mcp` is the live example: not in the gemspec, loaded in a memoized `require`/`rescue LoadError` (`Configuration#mcp_gem_present?`, `configuration.rb:502-512`), gated with the site toggle by `#mcp_enabled?` (`configuration.rb:560-562`), and `McpServer.build` returns nil when it is absent. A CI leg installs `--without mcp` and runs the suite to prove the feature no-ops. `rails_icons` gets a lighter version of the same treatment in `DocsUI::Icon`; the OG screenshot tooling (`shot-scraper`/chromium) is resolved at rake-task runtime and `og_generator.rb` is zeitwerk-ignored so it is never eager-loaded.

## One enumeration seam

`DocsKit::LlmsText.pages` (`llms_text.rb:68-73`) is the single place that answers "which pages does this request see?". `llms-full.txt`, the search index and the three MCP tools all call it, which is why making *it* version-aware made every AI surface version-aware at once. `LlmsText.renderable_for` (`llms_text.rb:87-89`) is the matching seam for "how do I render one" — it handles a live `Registry::Entry`, a `Snapshot::Entry`, and a site's older custom registry class that predates `#renderable`. Add a fourth consumer by calling these two, not by re-deriving the list.

## Generator idempotence is semantic, not byte-equality

Thor's `route` and `template` skip only a byte-identical line, which is useless against a site that wrote the same route in its own style. So the generator detects by meaning: `route_present?` matches the `controller#action` string in any quote style (`install_generator.rb:497-506`), `stimulus_registered?` matches either loader and either quote style (`install_generator.rb:558-560`), `merge_rubocop_config` round-trips through YAML and returns the original text when nothing changed (`install_generator.rb:450-464`), and `merge_agents_block` replaces only the text between the `<!-- BEGIN docs-kit -->` delimiters. When adding a step, make re-running it a genuine no-op and prove it with a spec that runs the generator twice.

## Site-owned files are skipped, never clobbered

`config/initializers/docs_kit.rb`, `Dockerfile`, `.claude/skills/write-docs-page/SKILL.md`, the doc registry, the sample pages and `application.tailwind.css` are the site's. The generator skips them when present and prints the template path for a manual diff (`create_initializer`, `install_generator.rb:104-112`; `create_dockerfile`, `211-219`). Gem-owned wiring goes the other way and is refreshed every run: `create_og_task` (`201-203`) and `create_dockerignore` (`225-227`, `force: true`). Decide which side a new file is on before writing the step. `SyncReport` warns about drift; it never edits.

## Tailwind only sees literal class strings

Tailwind scans the Ruby source, so an interpolated class name is tree-shaken out of the build. Class lists that must survive are written as literal strings — `Sidebar::MARKER_RESET` (`sidebar.rb:26`) says so explicitly. A render-time class that no source line spells literally needs an `@source inline(...)` entry in the site's `application.tailwind.css`. This is also why `bin/build-css` resolves the `daisyui` and `docs-kit` gem paths with `bundle show` and writes them into the generated `tailwind.sources.css`, and why it aborts when a gem can't be resolved: a silently missing `@source` ships an unstyled site.

## A component may render with no Rails request

Component specs render Phlex in isolation, and `DocsUI::MetaTags` may render in a static build, so anything reaching for `view_context` guards first: `Shell#csp_nonce` (`shell.rb:69`) returns nil when there is no view context and Phlex then omits the attribute, keeping the un-nonced markup unchanged; `Sidebar#current_path` rescues to nil (`sidebar.rb:116-120`); `ArchivedPage` deliberately omits the `Routes`/`Request` phlex-rails helpers because their bodies run `Rails.*` at class load. `Section#slugify` and `SearchIndex#slugify` each fall back to an ASCII slug when `String#parameterize` is unavailable.

## `raw(safe(...))` is for gem-authored markup only

Seven call sites bypass Phlex escaping, and every one of them emits markup the gem or a shape-checked site asset produced, never config free text: the Rouge-formatted code body and its static theme CSS (`code.rb:47`, `code.rb:123`), a shipped brand path (`brand_mark.rb:83`), a synced icon SVG (`icon.rb:27`), the theme-restore script whose only interpolation is `key.to_json` (`shell.rb:110`), the search snippet the index escaped itself, and `DocsUI::Logo`'s `markup:`/`file:` forms (`logo.rb:64`) — which `BrandLogo` shape-checks as an `<svg>` element at config time. Config free text (brand, description, labels) flows through `plain` or an ordinary attribute value and is escaped.
