# docs-kit

[![CI](https://github.com/mhenrixon/docs-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/mhenrixon/docs-kit/actions/workflows/ci.yml)

Shared [Phlex](https://www.phlex.fun) chrome for documentation sites built on
[daisyUI](https://daisyui.com). Extract the shell, sidebar, code blocks, theme
switcher, and page kit into one gem so multiple docs sites look identical and are
maintained in one place.

Reactive demos ([phlex-reactive](https://github.com/mhenrixon/phlex-reactive))
and Postgres-SSE transport ([pgbus](https://github.com/mhenrixon/pgbus)) are
**optional, runtime-detected** add-ons — docs-kit does not depend on them.

## What you get

A `DocsUI::` Phlex kit, configured once per site:

| Component | Role |
|-----------|------|
| `DocsUI::Shell` | The full HTML document: daisyUI Drawer shell, sticky topbar, sidebar, scrollable main. |
| `DocsUI::Sidebar` | Config-driven grouped nav with active-link highlighting + an optional version badge. |
| `DocsUI::ThemeSwitcher` | Zero-JS daisyUI theme dropdown (themes come from config). |
| `DocsUI::Icon` | Inline lucide SVG via `rails_icons`. |
| `DocsUI::BrandMark` | Inline developer/social brand logo (GitHub, Discord, …) for [topbar links](#topbar-links-repo--social); falls through to a lucide `Icon` for non-brand tokens. |
| `DocsUI::Code` | Rouge-highlighted code block (any of Rouge's ~200 languages) with an inline theme. |
| `DocsUI::Page` | Base class for a hand-authored doc page; renders inside `DocsUI::Shell`. |
| `DocsUI::Header` / `Section` / `Prose` / `Callout` | The page-authoring kit. |
| `DocsUI::Markdown` | GFM Markdown island — prose as Markdown, styled like `Prose`, fenced code through Rouge. |
| `DocsUI::Table` / `PropTable` | Reference tables — generic headers+rows, and a name/type/default/description preset. |
| `DocsUI::Endpoint` | HTTP method badge (coloured per verb) + monospace path; renders inline (drops into a `Section` description). |
| `DocsUI::FieldTable` / `ErrorTable` | API-reference presets over `Table` — an object's fields, and an endpoint's errors (Param column auto-hidden when unused). |
| `DocsUI::RequestExample` | One request declaration → one code tab per configured client (curl / JS / Ruby / Python by default). |
| `DocsUI::JsonResponse` | A Ruby Hash (or String) rendered as a pretty-printed JSON response block. |
| `DocsUI::OpenApiOperation` | One OpenAPI 3.x operation → a full endpoint reference (badge + tables + request tabs + response), composed from the kit. The `operation "id"` page helper is the front door. See [OpenAPI bridge](#openapi-bridge--an-endpoint-from-your-spec-no-hand-restatement). |
| `DocsUI::Example` | Base for a live example with `method_source`-extracted source. |
| `DocsUI::MarkdownAction` | The "Markdown" masthead action → the page's `.md` twin; `docs-nav` enhances it into copy-to-clipboard. |
| `DocsUI::SearchBox` / `SearchResults` | Topbar [search](#search) — a JS-off `GET` form + server-rendered results, enhanced into a `⌘K` palette by `docs-nav`. |

Plus `DocsKit::Registry` (in-memory docs registry mixin), `DocsKit::NavItem`
(sidebar link value object), `DocsKit::TopbarLink` ([topbar link](#topbar-links-repo--social)
value object), `DocsKit::MarkdownExport` ([every page as
Markdown](#every-page-is-also-markdown)), `DocsKit::SearchIndex` (the
[search](#search) index, built from the Markdown twins), and
`DocsKit::Controller#render_page`.

## Install

```ruby
# Gemfile
gem "docs-kit"
gem "daisyui", require: "daisy_ui"   # the daisyUI Phlex components
gem "phlex-rails"
gem "rails_icons", "~> 1.1"
gem "rouge"
# Optional, for reactive demos:
# gem "phlex-reactive"
```

## Keeping a site in sync

The install generator is the **upgrade path**, not a one-shot. Every step is
idempotent — safe to re-run on a years-old site — so bumping the gem and
re-running it pulls in whatever wiring newer docs-kit versions added (routes,
initializer hints, the AGENTS.md authoring block, the RuboCop cops) without
touching a byte you've edited. Your config initializer is skipped (never
clobbered); routes you already drew are skipped even if you wrote them in your
own style (single quotes, `to:` vs `=>`).

To upgrade an existing site:

```bash
bundle update docs-kit
bin/rails g docs_kit:install --sync   # wiring only — scaffolds no site content
# → act on any "manual cleanup needed" warnings it prints (see below)
bun run build:css                     # pick up any newly emitted classes
bundle exec rspec                     # confirm the site still boots + renders
```

`--sync` runs only the additive/wiring steps and **never** re-scaffolds
site-owned content (your `Doc` registry, your pages, your themed
`application.tailwind.css`). Drop `--sync` to also (re)scaffold missing content
files — Thor prompts before overwriting anything that exists.

### Version-aware migrations

Every install and `--sync` stamps the docs-kit version it ran into your config
initializer, as an inert comment on the first line:

```ruby
# docs-kit synced: v1.0.5
# frozen_string_literal: true
Rails.application.config.to_prepare do
  DocsKit.configure do |c|
    # ...
```

On the next `--sync` after a `bundle update docs-kit`, the generator reads that
stamp, works out the gap to the newly-installed version, and runs the **ordered
release-to-release migrations** in between — renamed config knobs, changed route
shapes, restructured templates — in sequence, then restamps to the new version.
A site created before the stamp existed (no comment) is treated as the earliest
version, so it gets every migration. Migrations are **warn-only-safe** exactly
like the drift report: what a step can't safely automate it prints as a manual
checklist (`migration steps to apply by hand:`), never a destructive rewrite of
a line you've edited. There are no migrations to apply yet — the mechanism ships
ahead of the first release that needs one, so the upgrade path is already in
place.

### One-time cleanup for sites created before these landed

`--sync` detects drift it can't safely automate and prints a checklist — it
**warns, never deletes**. The common items on sites scaffolded by older
generators:

| Drift | Why it's dead | Fix |
|-------|---------------|-----|
| `ApplicationController#render_page` defined by hand | `DocsKit::Controller#render_page` is included (the generator injects `include DocsKit::Controller`) | Delete the method — keep the `include`. |
| `app/helpers/icon_helper.rb` | docs-kit renders icons via rails_icons (`DocsUI::Icon`) | Delete the file. |
| Hand-pinned docs-kit lines in `config/importmap.rb` | the engine auto-pins the `docs-nav` controller and its assets | Delete the manual `pin`/`pin_all_from` lines for docs-kit. |
| `Dockerfile` stamped by an older docs-kit (`# docs-kit Dockerfile vX.Y.Z`) | docs-kit ships an optimized, multi-stage Dockerfile; a stale copy misses image-size wins | Diff yours against the current template (`lib/generators/docs_kit/install/templates/Dockerfile.tt` in the gem), adopt the changes or replace it. See [Upgrading your Dockerfile](#upgrading-your-dockerfile). |
| `app/assets/stylesheets/tailwind.sources.css` committed to git | `bin/build-css` regenerates it on every build with machine-specific absolute gem paths — the committed copy churns per machine/Ruby and no build consumes it. The generator adds the `.gitignore` entry, but gitignoring doesn't untrack an already-committed copy. | `git rm --cached app/assets/stylesheets/tailwind.sources.css` and commit. |

### Upgrading your Dockerfile

The generator ships two Docker files:

- **`.dockerignore`** is gem-owned — every `docs_kit:install` (or `--sync`) run
  **refreshes** it, so you always get the current build-context excludes
  (`node_modules`, `.git`, `log`, `tmp`, `spec`, `coverage`, …). It carries no
  site-specific content, so overwriting it is safe.
- **`Dockerfile`** is site-owned — the generator **never clobbers** it (you tune
  packages, the `CMD`, extra build steps). Instead it stamps a version marker
  (`# docs-kit Dockerfile v<VERSION>`) so `--sync` can tell you when yours is
  stale relative to the gem's current template.

When the site bundles `thruster` (a Rails 8 default), the generated Dockerfile
fronts Puma with Thruster (`CMD ["./bin/thrust", "./bin/rails", "server"]`) for
HTTP caching, compression, and X-Sendfile — and the generator scaffolds the
`bin/thrust` binstub if the app lacks one, since the exec-form CMD needs the
file to exist in the image. Thruster listens on the routed port
(`HTTP_PORT=3000` — Kamal's `app_port`) and proxies to Puma on `TARGET_PORT=3001`.
Without thruster in the *production* bundle (absent, or only in a
development/test group that `BUNDLE_WITHOUT` excludes) the CMD falls back to
plain `rails server` — never a thrust CMD that would crash at boot.

When `--sync` reports your Dockerfile is behind, compare it against the shipped
template and pull in the improvements (or replace it wholesale if you never
customized it):

```bash
# The template path is printed by the generator; it lives in the installed gem:
diff Dockerfile "$(bundle show docs-kit)/lib/generators/docs_kit/install/templates/Dockerfile.tt"
```

## Configure (per site)

```ruby
# config/initializers/docs_kit.rb
DocsKit.configure do |c|
  c.brand        = "phlex-reactive"
  c.brand_href   = "/docs"                                  # the DOCS home: brand, sidebar, and "← Docs home" masthead link (default "/")
  c.title_suffix = "phlex-reactive"
  c.themes       = %w[dark light synthwave retro cyberpunk dracula night nord sunset]
  c.version_badge = -> { "v#{Phlex::Reactive::VERSION}" }   # optional

  # Docs embedded in a bigger app? The way BACK to it — a labeled link rendered
  # once in the topbar, right after the brand. Unset (default) renders nothing.
  c.app_link = { href: "/", label: "Back to the app" }

  # Your own mark in the topbar + sidebar header instead of the text brand.
  c.brand_logo   = { paths: ["M4 2h9l5 5…Z"], viewbox: "0 0 81 45" }
  c.topbar_brand = :mobile_only                             # drop the desktop duplicate (default :always)

  # Repo/social links in the topbar (next to the theme switcher).
  c.topbar_links = [
    { href: "https://github.com/you/phlex-reactive", label: "GitHub", icon: :github },
  ]

  # Code blocks: a light theme by default, a dark theme on dark daisyUI themes.
  c.code_theme      = "Rouge::Themes::Github"               # base (light) theme
  c.code_theme_dark = "Rouge::Themes::Monokai"              # optional dark override

  # The sidebar derives from your registries — one heading → one registry.
  c.nav_registries = { "Docs" => Doc }
end
```

The nav is **derived from the registry**, so you never hand-write it. Each
registry maps a heading to its authored pages (`Doc.nav_items`); a page that
isn't written yet is skipped, so there are no dead links. Register a page with
one line (see [Add a page](#add-a-page)) and it appears in the sidebar.

The registry's page groups ("Getting started", "REST API", …) are the top level
of the rendered menu — each an open, collapsible section. The heading above them
only appears when you register **several** headings, and then as a static label
(no fold): a site with one registry gets no redundant "Documentation" level, and
nothing in the sidebar is indented deeper than group → page.

### The two homes, the brand link, and dark code themes

These knobs cover what sites used to shim by subclassing `DocsUI::Shell` or
overriding route helpers:

| Knob | Default | What it does |
|------|---------|--------------|
| `c.brand_href` | `"/"` | The **docs home** — the href of the topbar brand, the sidebar brand, and each page's "← Docs home" masthead link. Set it (e.g. `"/docs"`) when the docs live under a subpath, instead of subclassing `Shell` or overriding `root_path`. |
| `c.app_link` | `nil` | The **app home** — an opt-in `{ href:, label: }` link back to the application hosting the docs, rendered once in the topbar right after the brand (e.g. `{ href: "/", label: "Back to the app" }`). Unset renders nothing, so a standalone docs site is unchanged. External hrefs open in a new tab with `rel=noopener`. |
| `c.brand_logo` | `nil` | Your **brand mark**, rendered inside the brand anchor of BOTH the topbar and the sidebar header in place of the text `c.brand` (which stays the accessible name / `aria-label` fallback). Unset renders the text brand, byte-identical to before. Takes exactly one of five forms — see [The brand mark](#the-brand-mark) below. |
| `c.topbar_brand` | `:always` | Where the topbar renders the brand. At the drawer-pinned breakpoint (`lg:`) the sidebar brand is always visible, so the topbar copy is a duplicate — `:mobile_only` hides it there (`lg:hidden`). The default keeps today's markup verbatim. |
| `c.code_theme_dark` | `nil` | A second Rouge theme for **dark** daisyUI themes. `nil` keeps the single-theme behavior (fully backwards compatible). When set, `DocsUI::Code` also emits this theme's CSS scoped under `[data-theme=X] .code-highlight` for each shipped dark theme, so code blocks stay readable when the switcher flips to a dark theme. |
| `c.dark_themes` | daisyUI's built-in dark theme names | Which theme names count as dark for `code_theme_dark`. Intersected with `c.themes` at render time, so only shipped themes emit CSS. Override to name custom dark themes (e.g. `%w[zazu-dark]`). |

The dark restyle is **CSS-only** — daisyUI's `[data-theme]` selector is more
specific than the un-scoped base rule, so the theme switcher restyles code
blocks with no JavaScript and no flash. The Rouge CSS is inlined per block
(not part of the Tailwind build), so the [theme-sync invariant](#css--the-canonical-build)
is unaffected — a `code_theme_dark` doesn't need a CSS rebuild.

### The brand mark

`c.brand_logo` replaces the text brand in the shell chrome (topbar + sidebar
header) with your own mark — no more copying private `Shell`/`Sidebar` methods
that go stale on upgrades. It takes **exactly one** of five forms (mixing forms,
or a malformed value, raises at config time):

```ruby
c.brand_logo = { svg: "M4 2h9l5 5…Z", viewbox: "0 0 22 24", label: "Acme" } # one path-d
c.brand_logo = { paths: ["M4 2…Z", "M9 7…Z"], viewbox: "0 0 81 45" }        # multi-path wordmark
c.brand_logo = { markup: File.read("mark.svg") }                            # raw <svg> markup, embedded verbatim
c.brand_logo = { file: "app/assets/images/mark.svg" }                       # a .svg file, embedded inline
c.brand_logo = { src: "logo.png", alt: "Acme" }                             # an <img> from the asset pipeline
```

- The `svg:`/`paths:` forms render with `fill="currentColor"`, so the mark
  **recolors with the active daisyUI theme**. `markup:`/`file:` are embedded
  as-authored — use `currentColor` inside them to stay theme-adaptive. An
  `src:` `<img>` **cannot** inherit `currentColor` and won't adapt.
- `markup:`/`file:` embed your own SVG verbatim (they are your site's content,
  same trust domain as your views); both are shape-checked to be an `<svg>`
  element at config time, and a `file:` re-reads on change in development.
- `label:`/`alt:` name the mark for assistive tech; unset, the mark falls back
  to `c.brand`. The sidebar keeps the `version_badge` next to the mark.
- Sizing is fixed per surface (topbar `h-6`, sidebar `h-7`, landing hero `h-9`).
- `c.landing.logo` (the landing-hero mark) accepts the same five forms.

### Topbar links (repo & social)

Point readers at your source repo, chat, or socials from the topbar (next to the
theme switcher) with `c.topbar_links` — a list of `{ href:, label:, icon: }`.
Each renders as an **icon-only ghost button**; the `label` is its accessible name
(`aria-label` + tooltip). External links open in a new tab with `rel="noopener"`;
a site-relative `href` (e.g. `"/changelog"`) opens in place.

```ruby
c.topbar_links = [
  { href: "https://github.com/you/repo", label: "GitHub",  icon: :github },
  { href: "https://discord.gg/invite",   label: "Discord", icon: :discord },
  { href: "/changelog",                  label: "Changelog", icon: "history" }, # a lucide icon
]
```

`icon:` is either a **shipped brand mark** or **any lucide icon name**. lucide
dropped its brand logos, so the kit ships its own curated set of developer/social
marks as inline SVG (`DocsUI::BrandMark`) — no icon sync needed for these:

> `:github` · `:gitlab` · `:discord` · `:x` · `:rubygems` · `:bluesky` ·
> `:mastodon` · `:slack` · `:whatsapp` · `:telegram` · `:linkedin` · `:youtube` ·
> `:reddit` · `:stackoverflow`

Any other `icon:` value is treated as a **lucide** name and rendered through
`DocsUI::Icon` (so it must be in your synced set). Omit `icon:` to render the
`label` as a text button instead. `c.topbar_links` defaults to `[]` — a site that
sets nothing has an unchanged topbar. The marks use `fill: currentColor`, so they
recolor with the active daisyUI theme like the rest of the chrome.

### SEO & social sharing

Every page ships a complete SEO `<head>` — a meta description, **Open Graph**,
**Twitter Card**, canonical, favicon, and theme-color — so a link shared to
Slack/Discord/X/LinkedIn renders a rich card instead of a bare URL. It's all
config-driven (`DocsUI::MetaTags` reads `DocsKit.configuration`); a site that sets
nothing still gets a valid minimal card, so this is fully backwards-compatible.

```ruby
# config/initializers/docs_kit.rb
c.seo.description  = "What these docs cover, in one sentence."
c.seo.og_image     = "og/og.png"            # a path in YOUR app/assets/images/
c.seo.twitter_site = "@your_handle"
c.seo.site_url     = "https://docs.example.com"  # your canonical base URL
# c.seo.robots     = "noindex, nofollow"    # keep a staging/private site out of search
# c.seo.theme_color = "#0f172a"             # tints mobile browser chrome
```

**Per-page descriptions.** A `DocsUI::Page` sets its own with `description "..."`;
when it doesn't, the description is derived from the page's `#lead`, so existing
pages get a sensible per-page description for free:

```ruby
class Views::Docs::Pages::Installation < DocsUI::Page
  title       "Installation"
  description "Add the gem and render your first component."  # optional
  def lead = "..."   # used as the description when none is set
end
```

**The social-share image is your content, not the gem's.** docs-kit ships no OG
image — your landing page isn't docs-kit's to render. Until you set `c.seo.og_image`,
**no `og:image` tag is emitted** (a valid card, never a broken-image 404). Generate
one from your **own** landing page — it screenshots `/` into
`app/assets/images/og/{og,twitter,square}.png` — then point `og_image` at it:

```bash
bin/rails docs_kit:og   # needs a headless browser: shot-scraper or chromium/chrome
```

`og_image` is a **logical asset path in your pipeline** (`"og/og.png"`), resolved
through `image_url` to the digested `/assets/og/og-<digest>.png` URL Propshaft
serves — never the raw path, which 404s. So the image must be **precompiled**
(your Dockerfile's `assets:precompile` handles this at deploy); a configured
`og_image` that isn't in the pipeline fails loudly at deploy, not silently in
production. An absolute URL (`"https://cdn.example.com/card.png"`) is used verbatim.

`docs_kit:og` is a documented, manual routine (never run at deploy time), so a
machine without a browser is never blocked. Set `DOCS_KIT_OG_URL` to shoot a
deployed URL instead of booting locally, or `DOCS_KIT_SHOT` to force a browser CLI.

### Custom nav (advanced)

Sites that interleave several registries under a heading, or need custom
subgroups, set an explicit `c.nav` lambda instead — it wins over
`nav_registries`:

```ruby
c.nav = lambda do
  {
    "Demos" => Demo.grouped.transform_values { |demos|
      demos.map { |d| DocsKit::NavItem.new(href: "/demos/#{d.slug}", label: d.title, icon: d.icon) }
    },
    "Docs" => Doc.nav_items
  }
end
```

## Render

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include DocsKit::Controller   # adds #render_page
end

# any page controller
def show = render_page(Views::Docs::Pages::Installation.new)
```

`render_page(view)` renders the Phlex page with `layout: false`, because
`DocsUI::Shell` IS the full HTML document. phlex-rails still renders through a real
view context, so CSRF, `dom_id`, url helpers, and the reactive token signer all
work inside components.

### Add a page

One command scaffolds the page class **and** its registry line, both derived
from the title:

```bash
rails g docs_kit:page "Getting Started" --group=Guide
```

That writes `app/views/docs/pages/getting_started.rb` (a `DocsUI::Page` subclass
with a starter Markdown section) and injects `page "Getting Started", group:
"Guide"` into your `Doc` registry — so the page is routed and in the sidebar the
moment you write its content. Every derivation is overridable:

```bash
rails g docs_kit:page "OAuth" --group=Guide --slug=auth --view=OauthGuide
rails g docs_kit:page "Metrics" --group=Reference --eyebrow="Advanced"
rails g docs_kit:page "Guides Intro" --group=Guide --registry=Guide  # a differently-named registry
```

Re-running is idempotent (no duplicate registry line, no clobbered file). If your
registry still uses the legacy hash `entries [...]` form, the generator writes
the page but prints the entry for you to add by hand instead of corrupting it.

#### Under the hood

A page is a `DocsUI::Page` subclass — the generator just writes this for you:

```ruby
# app/views/docs/pages/getting_started.rb — Zeitwerk resolves the compact
# reference through the directory-implied namespaces (no nested modules).
class Views::Docs::Pages::GettingStarted < DocsUI::Page
  title "Getting Started"
  eyebrow "Guide"
  def lead = "Add the gem and render your first component."

  def content
    DocsUI::Section("Add the gem") do
      md <<~'MD'
        Components are plain Ruby classes.
      MD
      DocsUI::Code(<<~RUBY, filename: "Gemfile")
        gem "docs-kit"
      RUBY
    end
  end
end
```

…plus one line in the registry (`view_namespace` lets it derive the class):

```ruby
# app/models/doc.rb
class Doc
  extend DocsKit::Registry
  path_prefix    "/docs"
  view_namespace "Views::Docs::Pages"

  page "Getting Started", group: "Guide"   # slug "getting-started", view "GettingStarted"
end
```

`DocsUI::Page` includes the kit, so inside `#content` you call the components
directly — `DocsUI::Section(...)`, `DocsUI::Code(...)` — no `render … .new`.

### The authoring convention

One rule covers the whole kit: **the primary argument is positional; modifiers
are keyword arguments.**

```ruby
DocsUI::Header("Installation", eyebrow: "Guide")      # title positional
DocsUI::Section("Add the gem", id: "add", description: …)  # title positional
DocsUI::Code(source, lexer: :ruby, filename: "Gemfile")   # source positional
```

For the two wrappers that take **no** positional argument — prose and a
multi-language example — `DocsUI::Page` gives you lowercase helpers so a block
needs no parens:

```ruby
prose   { p { "Hand-authored prose." } }          # → DocsUI::Prose
example { |ex| ex.code(:ruby) { source } }         # → DocsUI::Example
md(<<~'MD')                                         # → DocsUI::Markdown
  A block of **Markdown**.
MD
```

The kit forms `DocsUI::Prose() { … }` / `DocsUI::Example() { … }` still work —
they just need the empty `()`, because a bare `DocsUI::Prose do … end` parses as
a constant reference (a Ruby `SyntaxError`). The lowercase helpers sidestep that
entirely, so they're the everyday path.

## Authoring with Markdown

Prose is the most-written content type — and the noisiest to hand-build from
`p`/`code`/`plain` calls. `DocsUI::Page` gives you `md(source)`: write a block of
GitHub-Flavored Markdown and it renders styled identically to `DocsUI::Prose`,
with fenced code routed through `DocsUI::Code` (Rouge).

```ruby
def content
  DocsUI::Section("Configure") do
    md <<~'MD'
      Set `brand` and `themes` in the initializer. Everything that differs
      between two sites is **configuration**, not markup:

      - `brand` — the topbar/sidebar heading,
      - `themes` — the ThemeSwitcher options.

      ```ruby
      DocsKit.configure { |c| c.brand = "My Docs" }
      ```

      | Option | Type   |
      |--------|--------|
      | brand  | String |
      | themes | Array  |
    MD
  end
end
```

That renders paragraphs, **bold**/*italic*, inline `code`, links, bullet/ordered
lists, block quotes, GFM tables (with the kit's table classes), and
strikethrough. A fenced ` ```ruby ` block is highlighted by Rouge exactly like a
hand-written `DocsUI::Code`; an unknown fence language falls back to plaintext.

Two things to know:

- **`md` is a lowercase page helper (like `prose`/`example`), so `md <<~MD … MD`
  needs no parens** — see [the authoring convention](#the-authoring-convention).
- **Use a single-quoted heredoc, `<<~'MD'`.** Then `#{…}` in your prose is
  literal text (Phlex escapes author text — no `html_safe`, no interpolation).

Markdown headings render as styled `h3`/`h4`. Document **structure and the "On
this page" TOC still come from `DocsUI::Section`** — keep section titles as
`Section`, and use Markdown headings only for sub-headings inside a section. Raw
HTML in the Markdown source is dropped (no `<script>`, no passthrough).

## Every page is also Markdown

Every doc page is **also** served as Markdown — append `.md` to its URL:

```bash
curl https://your-docs.example/docs/installation.md
```

returns a faithful GFM twin of exactly what `/docs/installation` renders —
headings, fenced code (with the right language), callouts as `> **Tip:**`
blockquotes, GFM tables, links (relative links absolutized to full URLs). You
write **nothing extra**: the twin is derived from the page's own render
(`DocsKit::MarkdownExport` walks the rendered HTML), so it can never drift from
the page the way a hand-written `to_text` copy does.

Each page's masthead carries a small **"Markdown"** action. With JavaScript off
it's a plain link that opens the raw `.md`; with JS on, `docs-nav` upgrades the
click into **copy-the-page-to-clipboard** — one click to paste a whole doc page
into an LLM. This is the machine-readable layer `llms.txt`, search, and MCP build
on.

Nothing to wire up — the install generator's route allows the `.:format`
segment, the engine registers the `text/markdown` MIME, and
`DocsKit::Controller#render_page` returns the twin for a `.md`/`.text` request.
To hide the masthead action site-wide (the `.md` route still works):

```ruby
DocsKit.configure { |c| c.page_markdown_action = false }
```

**Existing sites:** re-run `bin/rails g docs_kit:install` (or add `(.:format)`
to your `get "docs/:doc"` route) to enable the `.md` URLs. Sites that don't
re-run simply have no `.md` route match — HTML rendering is untouched.

## AI-assisted authoring

The install generator scaffolds the authoring contract in a **machine-readable**
form, so "document this endpoint" works out of the box — an agent doesn't have to
reverse-engineer the kit's idioms. Two files, both brand-substituted and
maintained in one place (the gem's templates):

- **`AGENTS.md`** (site root) — the cross-tool convention file (Claude Code,
  Cursor, Copilot, Aider, …). A terse, example-first authoring contract: the
  one-command page flow (`rails g docs_kit:page`), the `md <<~'MD'` prose idiom,
  that `DocsUI::Section` owns structure and the TOC, the reference-material
  helpers, and the invariants an agent must not break (the registry line is
  required, JS-off must work, themes ↔ CSS build). It links the live
  [Authoring pages](#the-authoring-convention) doc for depth.
- **`.claude/skills/write-docs-page/SKILL.md`** — a Claude Code skill: the recipe
  for the task (gather the subject → `rails g docs_kit:page` → write sections
  md-first → self-review against a checklist → run the gates). Its frontmatter
  targets "write / add / update a documentation page," so Claude Code reaches for
  it automatically.

If a site already has an `AGENTS.md`, the generator injects the docs-kit block
between `<!-- BEGIN docs-kit -->` / `<!-- END docs-kit -->` markers — your own
content is preserved, and a re-run only rewrites what's between the markers. An
existing skill file is never clobbered. `docs-kit new` inherits both files
automatically (it runs the install generator).

## Search

Every site gets search from the gem — no external service, no build step, no
JavaScript required. The topbar grows a search box; the reader types a query and
gets results grouped by page, each linking straight to the matching section.

The index is built **from the pages themselves**: each page's Markdown twin (the
same `.md` from the section above) is split on its `## ` headings into searchable
sections, so the index can never drift from what a page actually says — there is
no second registry to maintain. Scoring is plain Ruby: a title match outranks a
heading match outranks a body match, all query words must match (AND), and each
result carries a snippet with the term highlighted.

**Works with JavaScript off.** The box is a plain `GET` form; pressing Enter
lands on a fully server-rendered results page (`DocsUI::SearchResults`) through
the normal chrome, and each result's link jumps to the section anchor.

**Enhanced with JavaScript on.** The one `docs-nav` controller upgrades the box
into a command palette: press any configured shortcut to focus it, type to see
results appear inline (debounced, fetched as JSON from the same route), arrow
keys + Enter to jump to a result, and `Escape` to close. Each shortcut shows as a
`<kbd>` badge (server-rendered, so the hint is right with JS off too). If the
fetch ever fails, Enter still submits the form to the results page — never a dead
end.

### Keyboard shortcuts

The shortcuts that open the palette are configurable — `c.search_shortcuts`
defaults to `["/", "mod+k"]`:

```ruby
DocsKit.configure do |c|
  c.search_shortcuts = ["/", "mod+k", "s"]   # bind "/", ⌘K/Ctrl+K, and "s"
end
```

Each entry is a shortcut string: a bare key (`"/"`, `"s"`, `"?"`) or a chord
(`"mod+k"`, `"ctrl+shift+f"`). **`mod` is the platform command key** — `⌘` on
macOS, `Ctrl` elsewhere — so one entry works on every OS (and the `<kbd>` badge
shows `Ctrl` by default, swapping to `⌘` on macOS in JS). Modifiers accepted:
`mod`, `ctrl`, `shift`, `alt`, `meta` (aliases: `command`/`cmd` → `meta`,
`control` → `ctrl`, `option` → `alt`). A bare-key shortcut never fires while the
reader is typing in a field, and none of them collide with the browser —
`⌘K`/`Ctrl+K` is a *cancellable* accelerator (the palette calls `preventDefault`),
and `"/"` is never hijacked. Set `c.search_shortcuts = []` to bind no key (the
form still works). Whatever you configure drives both the key bindings and the
`<kbd>` hints from one source, so they can't drift.

### Other knobs

The controller ships in the gem (`DocsKit::SearchController`, `html` + `json`);
like llms.txt, the **route lives in your app**. The install generator scaffolds
it (above `docs/:doc`, so it isn't swallowed as a `:doc`):

```ruby
get "/docs/search" => "docs_kit/search#index", as: :docs_search
```

Two more knobs tune it (both optional — the defaults just work):

```ruby
DocsKit.configure do |c|
  c.search      = true           # default; set false to hide the box site-wide
  c.search_path = "/docs/search" # default; match your route if you move it
end
```

**Existing sites:** re-run `bin/rails g docs_kit:install` (it adds the route
idempotently), or paste the route line above into `config/routes.rb`.

## AI-readable docs (llms.txt)

Every site serves the two [llmstxt.org](https://llmstxt.org) artifacts, built
from the **registry** with zero authoring:

```bash
curl https://your-docs.example/llms.txt        # the index
curl https://your-docs.example/llms-full.txt    # every page, concatenated
```

`/llms.txt` is the index an agent fetches first: an H1 brand, an optional
one-line summary blockquote, one `##` section per nav group, and a
`- [Title](…/page.md)` link to each authored page's Markdown twin. `/llms-full.txt`
concatenates every page's Markdown (the same twin as `.md`) into one document,
separated by `---`. Both are `text/plain`, HTTP-cached (they revalidate on the
registry's content plus the gem version), and derived from the same registry the
sidebar uses — an unwritten page never appears, so there are no dead links.

Set the summary blockquote with the `tagline` knob (default `nil` → the line is
omitted):

```ruby
DocsKit.configure { |c| c.tagline = "The one-line description agents see." }
```

The controller ships in the gem (`DocsKit::LlmsController`); the **routes live in
your app** so you keep full control over path, auth, and omission. The install
generator scaffolds them:

```ruby
get "/llms.txt"      => "docs_kit/llms#index", as: :llms
get "/llms-full.txt" => "docs_kit/llms#full", as: :llms_full
```

**Existing sites:** re-run `bin/rails g docs_kit:install` (it adds the two routes
idempotently), or paste the two lines above into `config/routes.rb`.

## Add your docs to an agent (MCP)

`llms.txt` covers fetch-style consumption; **MCP** (the Model Context Protocol) is
the native one — a reader adds one URL and your docs become first-class agent
tools instead of scraped text. docs-kit ships a **read-only, stateless** MCP
server that any site can turn on with one gem + one route. It exposes three tools
over the SAME registry the docs render from (so an agent queries live docs, never
a stale copy):

| Tool | Returns |
|------|---------|
| `list_pages` | every authored page — `slug`, `title`, `group`, `url` |
| `get_page(slug:)` | one page's Markdown twin (the same `.md` twin `/llms.txt` links) |
| `search_docs(query:)` | ranked hits — `page_title`, `section_title`, `url`, `snippet` |

The `mcp` gem is **optional** — docs-kit depends on it in no gemspec list, and the
endpoint stays off (byte-identical to before) unless you opt in. Two steps:

```ruby
# Gemfile
gem "mcp"
```

```ruby
# config/routes.rb — the install generator scaffolds these COMMENTED; uncomment.
post  "/mcp" => "docs_kit/mcp#create", as: :mcp
match "/mcp" => "docs_kit/mcp#method_not_allowed", via: %i[get delete]
```

Then a reader connects — for Claude Code:

```bash
claude mcp add --transport http docs https://your-docs.example/mcp
```

and can ask Claude to search or read your docs, which now appear as tools. The
JSON-RPC is stateless (each `POST` is independent — no SSE session), so it works
behind the existing Kamal/Cloudflare deploy unchanged; `GET`/`DELETE` return
`405`. When enabled, `/llms.txt` grows a final `## MCP` line advertising the
endpoint so agents discover it.

`c.mcp` defaults to `true`, so once the gem + route are present the endpoint is
live. Set it `false` to keep it off even on a site that bundles the gem:

```ruby
DocsKit.configure { |c| c.mcp = false }
```

The endpoint is read-only over already-public content — writing docs is still
git, and private-docs auth is a host concern (the route is yours to wrap). Rate
limiting is the host's responsibility too (e.g. `rate_limit` in your base
controller). The server ships in the gem (`DocsKit::McpServer` /
`DocsKit::McpController`); the **route lives in your app**, like `llms.txt`.

## API docs — one request, every client tab

An endpoint example is a request shown in several clients (curl, JavaScript,
Ruby, Python, …) plus a JSON response. Writing each client by hand means a field
rename edits every language. `DocsUI::RequestExample` derives all the tabs from
**one** declaration; `DocsUI::JsonResponse` renders a Ruby Hash as a
pretty-printed response block.

```ruby
def content
  DocsUI::Section("Create a payment link",
    description: DocsUI::Endpoint.new(:post, "/v1/payment_links")) do

    render DocsUI::RequestExample.new(
      method: :post,
      path:   "/v1/payment_links",
      body:   { amount: 4900, currency: "usd", description: "Pro plan" }
    )

    render DocsUI::JsonResponse.new(
      { id: "plink_1a2b3c", object: "payment_link", amount: 4900,
        currency: "usd", url: "https://pay.example.com/plink_1a2b3c" }
    )
  end
end
```

`RequestExample` renders a `DocsUI::Example`, so the global sticky language
choice works exactly as with a hand-built example (pick Ruby once, every request
on the site shows Ruby). With JS off, every client snippet is visible stacked.

**Configure the client set and host once:**

```ruby
# config/initializers/docs_kit.rb
DocsKit.configure do |c|
  c.api_base_url   = "https://api.acme.com"                 # prefixed onto every path
  c.api_auth_header = "Authorization: Bearer sk_live_..."   # nil ⇒ no auth line

  # Swap a default for an SDK-flavored snippet, or add a new tab (e.g. a CLI):
  c.api_clients = {
    ruby: DocsKit::ApiClient.new(
      label: "Ruby", lexer: :ruby, filename: "app.rb",
      template: ->(req) { %(Acme.new.payment_links.create(#{req.pretty_body_json})) }
    ),
    cli: DocsKit::ApiClient.new(
      label: "CLI", lexer: :shell, filename: "acme",
      template: ->(req) { "acme payment_links create --amount #{req.body[:amount]}" }
    )
  }
end
```

The gem ships four generic-HTTP clients (`curl`, `javascript`, `ruby`,
`python`). A `c.api_clients` entry merges **over** them: reuse a token
(`ruby`) to replace that client with your SDK's snippet, or use a new token
(`cli`) to append a tab. Order is stable — reused tokens keep their position, new
ones append. Each `template` is a `(DocsKit::ApiRequest) -> String` callable;
the request exposes `#http_method`, `#url`, `#url_with_query`, `#headers`,
`#body?`, and `#pretty_body_json` so a template stays one short heredoc.

Pass `clients:` to a single call to filter/order the tabs:
`DocsUI::RequestExample.new(method: :get, path: "/v1/things", clients: [:curl, :ruby])`.

### OpenAPI bridge — an endpoint from your spec, no hand-restatement

If you already maintain an OpenAPI 3.x spec, you don't have to restate a single
method, path, field, or response in the docs. Point `c.openapi` at the spec and
one line renders the whole endpoint:

```ruby
# config/initializers/docs_kit.rb
DocsKit.configure do |c|
  c.openapi = Rails.root.join("openapi.yaml")   # String/Pathname (.json ⇒ JSON, else YAML) or a parsed Hash
end
```

```ruby
# app/views/docs/pages/invoices.rb
def content
  operation "createInvoice"          # the whole endpoint, derived from the spec
end
```

One `operation` call expands to a full `DocsUI::Section`:

| Spec source | Renders as |
|-------------|------------|
| `operationId` + `summary` + method/path | the Section title + a `DocsUI::Endpoint` badge |
| `description` | Markdown prose |
| `parameters` (query/path) | a `DocsUI::FieldTable` |
| `requestBody` schema (`$ref`, `allOf`, nested objects) | a `DocsUI::FieldTable` (nested names dotted: `customer.id`) |
| `4xx`/`5xx` responses | a `DocsUI::ErrorTable` (the error `type` is read from a response example when present) |
| `x-codeSamples` / `x-code-samples` | `DocsUI::Example` tabs (a lone sample → a plain `DocsUI::Code`) |
| no code samples | a generated `DocsUI::RequestExample` (curl / JS / Ruby / Python) |
| first `2xx` example (explicit or synthesized) | a `DocsUI::JsonResponse` |

The snippet URL uses each path parameter's `example` when the spec provides one
(so it's copy-pasteable), and query params appear only when they carry an
explicit `example` — a required-but-example-less param stays documentation-only.

Look up by `operationId`, or by verb + path for a spec whose operations have no
ids; append hand-authored prose with a block; filter the client tabs with
`clients:`:

```ruby
operation :delete, "/v1/invoices/{id}"                 # method + path lookup
operation "createInvoice", clients: %i[curl ruby]      # only these tabs
operation "createInvoice" do |op|                      # append prose in the section
  op.md("Idempotency keys are honored for 24 hours.")
end
```

An unknown `operationId` raises `DocsKit::OpenApi::OperationNotFound` naming the
available ids; an external/remote `$ref` raises `DocsKit::OpenApi::UnsupportedRef`.
Because the whole thing is composed from the kit, the `.md` twin, `llms.txt`,
search, and MCP surfaces derive from it for free.

**Out of scope:** authoring or validating the spec (bring your own), OpenAPI 2.0 /
Swagger, AsyncAPI, GraphQL SDL, external-file `$ref`s, and round-tripping docs
back to a spec.

## Scaffold a new docs site in one command

```bash
docs-kit new my-docs                       # → a complete, deployable docs app
docs-kit new my-docs --image mhenrixon/my-repo --service my-repo
```

`docs-kit new` runs `rails new` (propshaft + importmap + turbo/stimulus, no DB)
and applies docs-kit's application template, which:

- adds docs-kit + its deps to the Gemfile,
- runs `rails g docs_kit:install` (initializers, controllers, a Doc registry, a
  sample guide page, the Bun/Tailwind build, the docs-nav Stimulus wiring),
- syncs the lucide icons and builds the CSS,
- scaffolds Kamal (`config/deploy.yml`, `.kamal/secrets`, an optimized
  multi-stage `Dockerfile` + a `.dockerignore`) and a thin
  `.github/workflows/deploy-docs.yml` that calls the reusable workflow.

Then `cd my-docs && bin/dev`. Already have a Rails app? Run the install generator
instead:

```bash
rails g docs_kit:install
rails g rails_icons:sync --library=lucide
bun install && bun run build:css
```

Then add pages one command at a time — `rails g docs_kit:page "Title"
--group=Guide` (see [Add a page](#add-a-page)).

## Lint — the docs-kit RuboCop cops

docs-kit ships two custom cops so every site enforces the same authoring idioms
instead of hand-copying a cop file that drifts:

- **`DocsKit/RenderComponentPreferred`** — prefers the Phlex-kit helper form
  `DocsUI::Code(...)` over `render DocsUI::Code.new(...)` (autocorrectable).
- **`DocsKit/EscapedInterpolationInHeredoc`** — flags the `\#{...}` "escape tax"
  inside a double-quoted heredoc and steers you to a single-quoted delimiter
  (`<<~'RUBY'`), where `#{...}` is literal. Autocorrects when the heredoc has no
  live interpolation; otherwise it reports and leaves the fix to you.

Both are scoped to `app/views/docs/**/*` by default. The install generator wires
them into your `.rubocop.yml` automatically — two lines, merged idempotently
(your existing `inherit_gem` / `require` entries are preserved):

```yaml
# .rubocop.yml
require:
  - docs_kit/rubocop
inherit_gem:
  docs-kit: config/rubocop/docs_kit.yml
```

RuboCop is a **development-time** dependency of your app, never a runtime
dependency of docs-kit — `docs_kit/rubocop` requires `rubocop` lazily. Every
generated site already has `rubocop` in its Gemfile (via `rubocop-rails-omakase`
from `rails new`); if yours doesn't, add `gem "rubocop"` to the `:development`
group. Then `bundle exec rubocop` runs the docs-kit cops.

## Deploy a new docs site

The build + deploy is defined **once** in this gem's reusable workflow
(`.github/workflows/deploy.yml`). `docs-kit new` scaffolds the caller for you; to
wire it by hand a site adds five small things and it deploys to the
oss-infrastructure server (Kamal + GHCR + Cloudflare Tunnel).

**1. A thin caller** — `.github/workflows/deploy-docs.yml`:

```yaml
name: Deploy docs
on:
  release: { types: [published] }
  workflow_dispatch:
jobs:
  deploy:
    uses: mhenrixon/docs-kit/.github/workflows/deploy.yml@main
    with:
      image: mhenrixon/<repo>     # OWNER/REPO — see naming note below
      service: <repo>
    secrets: inherit
```

**2. `docs/config/deploy.yml`** — `service:` and `image:` MUST match the caller:

```yaml
service: <repo>
image: mhenrixon/<repo>
registry: { server: ghcr.io, username: mhenrixon, password: [KAMAL_REGISTRY_PASSWORD] }
builder: { arch: amd64, context: .., dockerfile: Dockerfile }   # repo root = build context
proxy:   { host: <%= ENV["DEPLOY_DOMAIN"] %>, app_port: 3000, ssl: false, healthcheck: { path: /up } }
servers: { web: { hosts: [<%= ENV["DEPLOY_HOST"] %>] } }
ssh:     { user: oss }
```

**3. `docs/Dockerfile`** — end the final stage with the matching label:

```dockerfile
LABEL service="<repo>"
```

**4. `docs/.kamal/secrets`** — `KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD`.

**5. GitHub** — a `docs` environment with secrets `SSH_PRIVATE_KEY`,
`DEPLOY_HOST`, `DEPLOY_DOMAIN`. (The registry password is the auto-provided
`GITHUB_TOKEN` — no PAT.)

> **Naming — use the repo name, not `<repo>-docs`.** `image`/`service` must be
> the calling repo's `OWNER/REPO`. Pushing `ghcr.io/mhenrixon/<repo>` from the
> repo's own Actions run auto-links the package to the repo, so `GITHUB_TOKEN`
> can both push (build job) and pull (deploy) it. A different name becomes an
> unlinked user-scoped package `GITHUB_TOKEN` can't pull → the deploy fails.

**First deploy per host:** run `kamal setup` (or `bin/deploy setup`) once to boot
any accessories (e.g. a Postgres accessory); the release workflow runs plain
`kamal deploy`, which doesn't boot accessories.

## CSS — the canonical build

daisyUI (and docs-kit) ship **no CSS** — your app builds Tailwind. To keep sites
identical, docs-kit standardizes on **Tailwind CSS v4 via the standalone CLI
(Bun)**.

`app/assets/stylesheets/application.tailwind.css`:

```css
@import "tailwindcss";
@plugin "daisyui" {
  themes: dark --default, light, synthwave, retro, cyberpunk, dracula, night, nord, sunset;
}

/* Tailwind must scan the Ruby that emits classes — the daisyUI gem, docs-kit,
   and your own views. */
@source "../../../app/views/**/*.rb";
@source "../../../../.bundle/gems/daisyui*/**/*.rb";
@source "../../../../.bundle/gems/docs-kit*/**/*.rb";
/* daisyUI Drawer classes are generated at render time, never literal — force them: */
@source inline("drawer drawer-content drawer-side drawer-toggle drawer-overlay {lg:}drawer-open drawer-end");
```

`package.json`:

```json
{
  "scripts": {
    "build:css": "bunx @tailwindcss/cli -i app/assets/stylesheets/application.tailwind.css -o app/assets/builds/application.css --minify",
    "watch:css": "bunx @tailwindcss/cli -i app/assets/stylesheets/application.tailwind.css -o app/assets/builds/application.css --watch"
  }
}
```

The themes in `@plugin "daisyui" { themes: ... }` **must** match
`DocsKit.configuration.themes`, or the switcher offers a theme the CSS doesn't
ship.

## JavaScript

docs-kit ships **one** Stimulus controller, `docs-nav`, auto-pinned by the engine
(like the daisyUI gem's dropdown controller). It's client-only UX polish — no
server round-trip:

- **Collapse persistence** — remembers which sidebar `<details>` the reader
  opened/closed (localStorage, namespaced by `config.nav_storage_key`), so the
  sidebar stays how they left it across navigations. The server always renders
  every section `open`, so with JS off the sidebar is simply fully expanded
  (progressive enhancement).
- **"On this page" auto-TOC** — collects the current page's `DocsUI::Section`
  anchors from the DOM and renders a live, scroll-spied table of contents in one
  of three placements, auto-hiding on short pages. No server-side knowledge of
  the headings, no per-page wiring.

### On this page (auto-TOC)

`DocsUI::Page` renders it automatically. The placement is a strategy — set the
site-wide default, override per page:

```ruby
DocsKit.configure { |c| c.on_page_default = :panel }   # :panel | :toggle | :sidebar | false

class Views::Docs::Pages::Installation < DocsUI::Page
  on_page :toggle   # override just this page; `false` opts out
end
```

| Mode | Placement |
|------|-----------|
| `:panel` (default) | A sticky card floating top-right of the content column. |
| `:toggle` | A sticky floating button (top-right) that opens a dropdown. |
| `:sidebar` | Nested under the active nav item in the left sidebar (GitBook-style). |

All three are driven by the same `docs-nav` controller reading the page's
headings, so they need zero per-page data. A page with fewer than 2 sections
hides the TOC. Scroll-spy highlights the section you're reading.

`DocsUI::Sidebar` already carries `data-controller="docs-nav"`. Register the
controller in the host app:

```js
// app/javascript/controllers/index.js
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
lazyLoadControllersFrom("docs_kit/controllers", application)
```

The **active nav item** needs no JS — it's server-rendered from the request path.

Reactive sites also load the auto-pinned `phlex/reactive/reactive_controller`
(from phlex-reactive) and register it eagerly:

```js
import ReactiveController from "phlex/reactive/reactive_controller"
application.register("reactive", ReactiveController)
```

## Releasing (maintainers)

Cut a release with the version-bumping Rake task — never `gem push` by hand:

```bash
rake release[1.0.0]           # bump → build-verify → commit → push → GitHub Release
rake release[1.1.0.rc1]       # a pre-release (auto-flagged --prerelease)
rake release[1.0.0,force]     # delete + re-create an existing tag/release
```

The task (on `main`, clean tree only) bumps `lib/docs_kit/version.rb`, updates the
lockfiles (incl. `docs/Gemfile.lock`), verifies `gem build --strict`, commits,
pushes, and creates the GitHub Release. Publishing the tag fires
`.github/workflows/release.yml`, which runs the suite, rebuilds + content-checks
the gem, signs it with Sigstore, and pushes to RubyGems over **OIDC trusted
publishing** (no API token stored anywhere).

### One-time setup (before the first release)

Trusted publishing needs two things wired once — the first release fails without
them:

1. **RubyGems pending trusted publisher.** On [rubygems.org](https://rubygems.org)
   → your profile → *Trusted Publishers* → *Create*, add a **pending** publisher
   (works for a gem not yet pushed) with:
   - Gem name: `docs-kit`
   - Repository: `mhenrixon/docs-kit`
   - Workflow filename: `release.yml`
   - Environment: `rubygems`
2. **GitHub `rubygems` environment.** Repo *Settings → Environments → New
   environment* named `rubygems` (the `publish-rubygems` job pins it and requests
   `id-token: write`). Add reviewers there if you want a manual gate before a push.

After the first successful push the pending publisher converts to a normal one; no
further setup is needed for later releases.

## License

MIT.
