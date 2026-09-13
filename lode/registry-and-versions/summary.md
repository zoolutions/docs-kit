# Registry and versions

Where a site's page list comes from, and how an archived version swaps it out underneath everything.

## `DocsKit::Registry` — the mixin

A site's registry class does `extend DocsKit::Registry`. Two authoring styles share one lookup API.

**The `page` DSL (v2)** — the default. `page "Installation", group: "Guide"` (`registry.rb:65-75`) appends a frozen Hash in declaration order, which is sidebar order. Slug derives from `title.parameterize`, view from `title.parameterize(separator: "_").camelize`; both are overridable with `slug:`/`view:`, and `icon:` is optional. `path_prefix` (default `"/docs"`) and `view_namespace` are class-level declarations.

**The hash `entries` API** — for a registry with a bespoke schema. The site declares `entries [...]` and writes its own `initialize`/readers/`view_class`.

A registry uses one style. `page` raises `Registry::Error` when `@entries` is set, and `entries` raises when `@pages` is non-empty (`registry.rb:53-59`, `65-75`).

The shared API: `.all` (`99-105`, built **fresh on every call** — instances are cheap and a site may resolve view classes that change under code reload in development), `.from_slug`, `.grouped` (grouped by `group_by_attribute`, default `:group`, preserving order within a group), and `.nav_items` (`120-126`) — `{ group => [NavItem] }` for authored pages only.

`Registry::Entry` is the default instance for a v2 `page`: readers plus `#href` (`"#{path_prefix}/#{slug}"`) and `#view_class` (`145-149`), which `safe_constantize`s `"#{view_namespace}::#{view_name}"` and returns nil until the class is written. `#renderable` (`154-156`) is `view_class&.new`.

**Authored means a resolvable `view_class`.** `nav_items` filters on it, and so does `LlmsText.pages`. That is the one mechanism preventing a dead link to a declared-but-unwritten page across the sidebar, `llms.txt`, search and MCP. Note the filter is `respond_to?(:view_class) && view_class` — an `entries`-style registry whose instances don't define `view_class` contributes no nav items at all.

## `DocsKit::DocVersion` — one version

A `Data.define(:id, :label, :ref, :current, :noindex)` (`doc_version.rb:22`). Defaults matter: `label` falls back to `id.to_s`; `current` defaults false; **`noindex` defaults to the inverse of `current`** — archived copies are noindex'd so search engines keep pointing at the live docs, overridable per version with `noindex: false`.

`#path_prefix` (`doc_version.rb:55-57`) is `""` for the current version and `"/#{id}"` for an archived one, so existing sites' URLs and SEO are untouched. Named `DocVersion`, not `Version`, because `lib/docs_kit/version.rb` already owns that file slot for `DocsKit::VERSION`.

Configuration reads: `#versions` normalises the list, `#current_version` is the entry marked `current: true` else the first entry else nil, `#version(id)` is a strict lookup, `#resolve_version(id)` is the degrade-to-current rule, `#versioning_enabled?` needs two or more.

## `DocsKit::Snapshot` — an archived version's content

A snapshot lives at `<config.snapshots_path>/<version id>/`: a `manifest.json` plus one `.md` file per page. `snapshots_path` defaults to `Rails.root/"docs_snapshots"` under Rails, nil outside it (the standalone suite passes explicit paths and points at `spec/fixtures/snapshots/`).

`Snapshot` speaks the **same duck type as a registry** — `#all`, `#from_slug`, `#nav_items`, plus `#nav_groups` and `#markdown_for(slug)` — which is what lets an archived version render through today's chrome with only its content frozen. `Snapshot::Entry` mirrors `Registry::Entry` (`#slug`/`#title`/`#group`/`#icon`/`#href`/`#view_class`/`#renderable`); its `#view_class` returns the truthy `DocsUI::ArchivedPage` constant, so the `select(&:view_class)` authored-page filter passes unchanged, and `#renderable` returns `DocsUI::ArchivedPage.new(entry: self)`.

`Snapshot.for` (`snapshot.rb:31-44`) memoizes per `[version id, root]` and invalidates on `manifest.json`'s mtime. `Snapshot.reset_cache!` clears it.

Failure is silent by design, in both directions: a missing directory or unparseable manifest reads back as an empty snapshot (`#read_manifest`, `snapshot.rb:140-149`, rescuing `JSON::ParserError` and `SystemCallError`), and an unreadable page file renders as `""`. A version configured before its snapshot is written must not take the site down. `SCHEMA = 1` is stamped by the writer so a future format change is detectable rather than silently misread.

## How a request picks a source

`DocsKit::Scope.version` is set once per request by `Controller#render_page` or `Scoping`. Two readers branch on it and nothing else has to:

- `Configuration#nav_groups` — an archived version's nav comes from the snapshot manifest.
- `LlmsText.pages` — an archived version enumerates the snapshot instead of the live registries.

`DocsUI::ArchivedPage` renders an entry's frozen Markdown through `DocsUI::Shell` + `DocsUI::Markdown`. It deliberately does **not** include the `Routes`/`Request` phlex-rails helpers, whose bodies run `Rails.*` at class load and would make the constant — and therefore `Snapshot::Entry#view_class` — unloadable in a Rails-free render. Every kwarg defaults, so even a naive `entry.view_class.new` renders an empty page rather than raising.

## Related

- `../config/summary.md` — `nav_registries`, `versions`, `snapshots_path`
- `../ai-surfaces/summary.md` — `LlmsText.pages`, the shared enumeration seam
