# Config — `DocsKit::Configuration` and the value objects

`lib/docs_kit/configuration.rb` (656 lines) is the whole surface a site tunes. `DocsKit.configuration` memoizes one instance; `DocsKit.configure { |c| … }` yields it; `DocsKit.reset_configuration!` replaces it (the suite calls this in a `before` hook).

## Shape

36 top-level knobs. 33 are plain `attr_accessor`/`attr_writer`/`attr_reader`; three have hand-written writers because assignment does work:

- `nav=` (`configuration.rb:60`) sets a `@nav_explicit` flag. The flag, not object identity, is what makes `#nav_groups` prefer an explicit lambda — so *any* assigned lambda wins, even one that resolves to `{}`.
- `brand_logo=` (`configuration.rb:205`) clears the memo and stores the raw value, because `#brand_logo` memoizes a built `BrandLogo` (a `file:` mark reads its SVG on build, and re-normalising per render would repeat that IO).
- `topbar_brand=` (`configuration.rb:219`) validates against `TOPBAR_BRAND_MODES` (`%i[always mobile_only]`) and raises `ArgumentError` on anything else.

Two knobs are nested config objects, lazily built and memoized so a `c.seo.x = …` block mutates the instance the Shell later reads: `#seo` → `DocsKit::SeoConfig` (11 accessors: description, og_image, og_type, twitter_card, twitter_site, twitter_creator, locale, site_url, favicon, robots, theme_color) and `#landing` → `DocsKit::LandingConfig` (8: logo, eyebrow, title, lead, install, doc_index, ctas, features).

Several writers pair with a normalising reader, and the reader is the one to call — never the ivar: `@topbar_links` → `#topbar_links` (coerces each entry through `TopbarLink.from`), `@versions` → `#versions` (`DocVersion.from`), `@app_link` → `#app_link`, `@search_shortcuts` → `#search_shortcuts` (`Shortcut.parse_list`, dropping anything unparseable), `@api_clients` → `#api_clients` (merged **over** `ApiClient::DEFAULTS`, so a reused token replaces that tab in place and a new token appends), `@snapshots_path` → `#snapshots_path`.

## The derived readers

- `#nav_groups` (`configuration.rb:592-599`) — the sidebar source. Three branches, in order: an **archived** version in `DocsKit::Scope` wins outright and the nav comes from that version's snapshot manifest (hrefs already version-prefixed, so an archived page never links into the live docs); else an explicit `#nav` lambda; else derived from `#nav_registries` via `#nav_groups_from_registries`, which drops a heading whose registry has no authored pages so no empty group renders.
- `#default_theme` → `@default_theme || themes.first`; `#title_suffix` → `@title_suffix || brand`; `#nav_storage_key` → a slug of the brand. Each is a "configured value or a derived default", never nil.
- `#search_enabled?` (`567-569`) and `#mcp_enabled?` (`560-562`) share a shape: the site toggle **and** a capability. Search needs a non-empty `@search_path` to submit to; MCP needs the optional `mcp` gem to be loadable (`#mcp_gem_present?`, memoized across both outcomes so a site without the gem doesn't pay a failed require per request).
- `#versioning_enabled?` (`398-400`) is `versions.size > 1` — one configured version is not worth a switcher, and an unconfigured site stays byte-identical.
- `#resolve_version(id)` (`391-393`) is `version(id) || current_version`: an unknown or missing id degrades to the current docs rather than 500ing. `DocsKit::Controller#render_page` and `DocsKit::Scoping` both call it, so the rule is stated once.
- `#code_theme_class` / `#code_theme_dark_class` resolve a String name through `#resolve_theme`, which rescues `NameError` to nil — a typo'd theme name must not crash every code block. The light reader then falls back to `DEFAULT_CODE_THEME`; the dark one returns nil, which `DocsUI::Code` reads as "emit no dark CSS".
- `#dark_themes_shipped` (`641-643`) is `themes & dark_themes`, in `themes` declaration order, so a dark theme the Tailwind build never generated emits no dead CSS.
- `#on_page_default` / `#normalize_on_page` coerce to `ON_PAGE_MODES` (`%i[panel toggle sidebar]`) or `false`; a bare `true` means `:panel`. Anything else raises `ArgumentError`.

## Value objects

All are `Data.define` with a keyword `initialize` supplying defaults, and most carry a `.from` that passes an existing instance through and coerces a Hash with `transform_keys(&:to_sym)` — so a YAML- or JSON-sourced config loads cleanly.

| Object | File | Role |
|---|---|---|
| `NavItem` | `nav_item.rb` | one sidebar link: `href`, `label`, optional `icon` |
| `TopbarLink` | `topbar_link.rb` | a topbar external link; `icon` symbolised on build; `#external?` drives `target=_blank` + `rel=noopener` |
| `DocVersion` | `doc_version.rb` | one documentation version; see `../registry-and-versions/summary.md` |
| `SearchHit` | `search_hit.rb` | one ranked result, with `#label` and the `#as_json` shape the palette fetches |
| `ApiClient` | `api_client.rb` | one language tab for `DocsUI::RequestExample`: label, lexer, filename (String or proc), and a `(ApiRequest) -> String` template |
| `ApiRequest` | `api_request.rb` | one declared request, handed to every client template so a snippet is authored once |
| `Shortcut` | `shortcut.rb` | a parsed search-palette chord; a plain class, not `Data` |
| `BrandLogo` | `brand_logo.rb` | the normalised brand mark; a plain class |
| `SeoConfig`, `LandingConfig` | `seo_config.rb`, `landing_config.rb` | plain accessor objects, because each field is individually assignable in a `c.seo.x = …` block |

`Shortcut` exists because three places must agree on one chord: the config surface, the server-rendered `<kbd>` hint (`#label`), and the `docs-nav` matcher (`#to_h`, serialised to JSON). `"mod"` stays abstract on the server — ⌘ on mac, Ctrl elsewhere — and the browser resolves it, so one config entry works on every platform.

`BrandLogo` accepts exactly one of five form keys (`svg:`, `paths:`, `markup:`, `file:`, `src:`); giving none or several is ambiguous and raises. The `markup:`/`file:` forms are shape-checked as an `<svg>` element at config time, because `DocsUI::Logo` embeds them verbatim through `raw(safe(...))`.

## Related

- `../components/summary.md` — the components that read these knobs
- `../core/summary.md` — `Scope`, which `#nav_groups` consults
