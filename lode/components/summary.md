# Components — the `DocsUI::` chrome and the client controller

`app/components/docs_ui/` holds 30 Phlex component classes plus `page_helpers.rb` (the `DocsUI::PageHelpers` module). `DocsUI` is a `Phlex::Kit`, so `DocsUI::Code(src)` and `render DocsUI::Code.new(src)` are the same call; the shipped RuboCop cop `DocsKit/RenderComponentPreferred` steers authored doc pages to the former.

## The document: `Shell`

`DocsUI::Shell` **is** the whole HTML document — `doctype`, `<html>`, `<head>`, `<body>` — which is why every controller renders it with `layout: false`. Structure (`shell.rb`):

- `<html data-theme=…>` from `config.default_theme`.
- `#render_head` (`75-95`): `<title>` joining the page title and `config.title_suffix` with `" · "`, charset, viewport, `DocsUI::MetaTags`, `csrf_meta_tags`, `csp_meta_tag`, the two Turbo morph metas, one `stylesheet_link_tag` per `config.stylesheets`, the theme-restore script, `javascript_importmap_tags`.
- `#theme_restore_script` (`107-123`) applies the persisted theme **before first paint**, so there is no flash of the server default. It reads the same `docs-kit:<site>:theme` localStorage key `docs-nav` writes, re-applies on `turbo:load`, and carries the request's CSP nonce (nil off a request, which Phlex omits).
- `data-controller="docs-nav"` sits on `<body>`, not the sidebar — the shared ancestor of both the sidebar and the content column, because the `:panel`/`:toggle` TOC lives in the content.
- `#shell` (`127-151`) is the daisyUI `Drawer`: `lg:drawer-open` pins the sidebar on desktop and the hamburger toggles it on mobile. The content column is `div(id: "docs-content")` — the Markdown-export anchor — with the topbar, sidebar and TOC deliberately **outside** it so they never bleed into a `.md` twin.
- `#topbar` (`154-170`): hamburger (mobile only), brand anchor at `config.brand_href`, the opt-in app-home link, `SearchBox` when `config.search_enabled?`, `TopbarLinks`, `ThemeSwitcher`.
- `#topbar_brand_classes` (`176-179`) appends `lg:hidden` when `config.topbar_brand == :mobile_only`, deduplicating the mark at the breakpoint where the sidebar brand is already visible. `:always` keeps the pre-knob classes verbatim.
- `#brand_mark` renders `DocsUI::Logo` when `config.brand_logo` is set, else `plain config.brand`. `Sidebar` has the same method at a larger size (`h-7` vs `h-6`), and the text brand remains the mark's accessible-name fallback.

## The nav: `Sidebar`

Driven entirely by `config.nav_groups`, an ordered `{ heading => { subgroup => [NavItem] } }`. Groups whose value is nil or empty are rejected first (`sidebar.rb:37`); the heading label renders **only when more than one group survives** (`labeled: groups.size > 1`) — a single-registry site's masthead already labels the sidebar.

A heading renders as a static `li.menu-title`, never a `<details>`, so subgroups stay at the menu's top level. A subgroup renders as `li > details[open]` — server-rendered open, which is the whole progressive-enhancement story: with JS off the sidebar is simply fully expanded. `MARKER_RESET` (`sidebar.rb:26`) suppresses the native disclosure triangle, written as a literal class string because Tailwind tree-shakes interpolated ones. A collapsible `<summary>` must **not** carry `.menu-title`: daisyUI's caret layout rule is `summary:not(.menu-title)`, and a `.menu-title` summary loses the grid and drops its chevron below-left.

Active state is a strict `request.path == item.href` match (`#link_classes`, `111-114`), server-side, no JS. `#current_path` rescues to nil so an isolated render works.

## The page: `Page`, `Section`, and the authoring helpers

`DocsUI::Page` is the base class an authored page subclasses. Class-level `title`, `eyebrow`, `description`, `on_page`; instance `#lead` and `#content` (which raises `NotImplementedError` until written). `#view_template` renders `Shell` with `description: self.class.description || lead`, so a page gets a sensible SEO description for free.

The masthead nav carries `data-md-skip` — it is chrome, so "← Docs home" and the "Markdown" action never reach the `.md` twin. `#home_href` is `config.brand_href`, never the host's `root_path`: on an app-embedded site the application root is not the docs landing.

`DocsUI::Section` owns page structure and the TOC. It resolves its anchor id at render time and de-duplicates it across the page through Phlex's shared render `context` (`#unique_id`, `section.rb:86-92`): colliding bases get a `-1`, `-2` … suffix, and a title that slugifies to empty falls back to `"section"`. Its `description:` accepts three forms and the order of the branches is load-bearing — a Phlex component also responds to `#call`, so `when Phlex::SGML` must be matched before the callable branch or the component would be `instance_exec`'d instead of rendered (`section.rb:61-70`).

`DocsUI::PageHelpers` supplies the lowercase `md` / `prose` / `example` helpers — the no-positional-argument path that avoids the parens-with-blocks gotcha.

## Code, Markdown, MetaTags

`DocsUI::Code` resolves its lexer in order: explicit `lexer:`, then a guess from `filename:` via Rouge's own filename globs, else ruby; an unresolvable language falls back to `config.code_lexer_fallback` ("plaintext") and never raises. It injects its own Rouge theme CSS inline (nonced), so no separate stylesheet asset is needed, and stamps `data-md-lang` with the **resolved** Rouge tag so the Markdown export emits a ` ```lang ` fence without re-resolving.

`DocsUI::Markdown` parses GFM with commonmarker and walks the AST emitting Phlex nodes — it never `raw`s commonmarker's HTML. So author text is Phlex-escaped, `#{}` in prose renders literally, fenced blocks delegate to `DocsUI::Code`, and the wrapper reuses `Prose::CLASSES` verbatim. Raw HTML in the source is dropped (`html_block`/`html_inline` nodes are skipped) with no config to enable it. Markdown headings render as styled `h3`/`h4`; document structure and the TOC stay with `Section`.

`DocsUI::MetaTags` emits description, Open Graph, Twitter Card, canonical, favicon, robots and theme-color from `config.seo` plus the page title/description. A relative `og_image` resolves through `image_url` to the digested `/assets` URL; an absolute URL passes through; nil emits no tag. Canonical and `og:url` come from `config.seo.site_url` else the request URL, and both are omitted off a request. The full contract is `../../.claude/rules/seo.md`.

## The one client controller

`app/javascript/docs_kit/controllers/docs_nav_controller.js` (619 lines) is the only Stimulus controller the gem ships, auto-pinned by the engine through `config/importmap.rb`'s `pin_all_from`. It does collapse persistence (localStorage, keyed by summary text, namespaced by `storageKey`), the auto-TOC in three placements, scroll-spy via `IntersectionObserver`, and the debounced search palette. Each behaviour degrades to a harmless no-op: no TOC on the page, no-op; JS off, the server-rendered page still works.

`config/importmap.rb` and `REGISTER_LINE` in the install generator both insist on `eagerLoadControllersFrom`, not `lazyLoadControllersFrom`: the default `controllers/index.js` imports only the eager one, so a `lazyLoadControllersFrom` call with no import throws a `ReferenceError` that aborts the module and registers **zero** controllers.

## Related

- `../config/summary.md` — every knob these components read
- `../ai-surfaces/summary.md` — `#docs-content` and `data-md-skip` as the export contract
- `../../.claude/rules/seo.md` — the OG-image rules
