# Changelog

## [Unreleased]

### Upgrading from 1.4

Nothing to change for a site that registers the controller with
`eagerLoadControllersFrom("docs_kit/controllers", application)`, as the
generated `index.js` does: `docs-nav` still registers on every page. It is no
longer preloaded, so on docs pages the eager loader's `import()` fetches it
one request later instead of from the preload cache. To keep the preload, set
`config.docs_kit.preload = true` in `config/application.rb`.

### Added

- **`config.docs_kit.controllers_under`** (default `"docs_kit/controllers"`)
  sets the auto-pin's module namespace. `"controllers"` pins the controller as
  `controllers/docs_nav_controller` (same asset), so the host's own loader for
  `controllers` finds it, with no docs-kit line in `index.js`; with
  `lazyLoadControllersFrom("controllers", application)` a page fetches it only
  if it renders `data-controller="docs-nav"`. Set it in
  `config/application.rb`. (#107)

### Changed

- **`docs-nav` is no longer preloaded on every page.** The auto-pin took
  importmap-rails' default `preload: true`, so in a host whose docs share the
  application's import map every page, docs or not, carried a
  `<link rel="modulepreload">` for the 24 KB controller, and a host `pin` with
  `preload: false` could not override it (a `pin_all_from` directory expands
  over plain pins). `config.docs_kit.preload` (default `false`) is now the
  pin's `preload:`: `true` restores 1.4's behaviour, an entry-point name
  (importmap-rails 2.x) preloads it only where that entry point is rendered.
  (#107)

### Fixed

- **One documented registration.** The README and the pin file's header now
  point at one "Registering the controller" section. The README no longer
  recommends `lazyLoadControllersFrom("docs_kit/controllers", application)`,
  which in a host with its own controllers requests
  `docs_kit/controllers/<identifier>_controller` for every host
  `data-controller` and logs a "Failed to autoload controller" error for each,
  on every page. (#107)

## [1.4.0] — 2026-10-15

### Upgrading from 1.3

Nothing to change for a site whose initializer configures docs-kit in a
`to_prepare` block, as the generated one does. Three things now fail loudly
instead of later or never: a broken `brand_logo` raises at boot, in
development too; mutating a registry DSL or `DocsUI::Page` macro value in place
raises `FrozenError`; so does mutating one of docs-kit's constants.

### Fixed

- **A cold archived version is built once, however many requests ask.**
  `DocsKit::Snapshot.for` cached snapshots in an unguarded class ivar, so
  threads that missed a version together each read and parsed its
  `manifest.json` and raced to store it. The cache is now per Ractor and its
  check-then-set runs under a lock; `Configuration#openapi_document`'s
  mtime-checked memo likewise. (#91)
- **No per-render constant lookups once the app has booted.** The engine now
  calls `DocsKit.finalize!` once the host has configured the kit, with no app
  code: the Rouge code themes and every registered page's view class are
  resolved once into frozen maps instead of `Object.const_get` /
  `safe_constantize` on every render, and the brand logo, SEO, landing and
  optional-mcp memos are filled at boot rather than by whichever request comes
  first. `DocsKit.configure` re-opens it, and a theme assigned directly
  afterwards still wins. Outside Rails, call `DocsKit.finalize!` yourself. (#91)

### Changed

- **Finalized after boot in every environment, and after every reload.** The
  engine finalizes in `after_initialize` in development too. With code
  reloading on, it finalizes again after each reload, once the host's
  `to_prepare` configure has re-run and re-opened the configuration, so the
  resolved page views are the reloaded classes. The host's callables (`brand`,
  `nav`, `version_badge`, `importmap`, ...) are kept as given, never frozen:
  they may close over app state, so `DocsKit.configuration` stays
  main-Ractor-only and finalizing never fails on one. (#91)
- **Boot-time values are frozen.** The registry DSL (`page`, `path_prefix`,
  `view_namespace`, `group_by_attribute`) and `DocsUI::Page`'s `title`,
  `eyebrow`, `description` and `on_page` macros deep-freeze what they are
  given (Ractor-shareable), as do the gem's own constants, and
  `DocsKit.configuration` is built at load rather than on first read. Code
  that mutated one of those values in place after declaring it now raises
  `FrozenError`. (#91)
- **A broken `brand_logo` fails at boot.** `DocsKit.finalize!` builds the logo,
  so a missing file or non-SVG markup raises when the app boots, in every
  environment, instead of on the first render. (#91)
- docs-kit is held to [conformance-kit](https://github.com/zoolutions/conformance-kit)
  0.4 in CI: the rubocop-thread_safety cops, thread and fiber contention specs,
  a Ruby 4.0 Ractor canary (search index, llms.txt, the sidebar tree) and
  `conformance-audit --strict`, whose allowlist names Rails' and Thor's class
  state on the engine, controllers and generators by `ancestor:` rule. (#91)

## [1.3.0] — 2026-10-13

### Fixed

- **Markdown links drop a script-bearing href.** `[text](javascript:…)`,
  `data:`, `vbscript:` and any other scheme outside http(s), `mailto:` and
  `tel:` now render the link text with no `<a>` (Phlex already refused
  `javascript:`; `data:` and the rest slipped through). Scheme-less hrefs are
  unchanged. The same guard `DocsUI::Markdown` images have.

### Added

- **A per-request `brand` and `title_suffix`.** Both accept a zero-arity
  callable (`c.brand = -> { Current.tenant_name }`), evaluated on every render:
  the topbar, sidebar header, `<title>`, `og:site_name`, llms.txt and the MCP
  server name show that request's value. A callable brand needs an explicit
  `c.nav_storage_key`; `DocsKit.configure` raises without one. New readers
  `Configuration#brand_text` / `#title_suffix_text`; a String brand renders
  exactly as before. (#92)
- **Markdown images render.** `![alt](path "title")` in an `md` island now
  renders a lazy-loaded `<img>` (it rendered nothing before). In a Rails view
  a relative path resolves through the site's asset pipeline (`image_path`;
  off a request it is kept as written); an absolute,
  protocol-relative or root-relative URL is kept as written; the alt is the
  description's plain text. A `javascript:`, `data:` or other non-http(s)
  scheme renders no image. The page's `.md` twin exports it back to
  `![alt](src)`. (#94)
- **A dedicated docs import map.** `c.importmap_entry_point` (default
  `"application"`) and `c.importmap` (an `Importmap::Map` or a callable
  returning one, resolved per render) choose what the Shell's
  `javascript_importmap_tags` loads, and `config.docs_kit.auto_pin = false` (in
  `config/application.rb`) keeps the gem's `docs-nav` pin out of the host's
  shared map. Unset, the head is unchanged. (#93)
- **`DocsUI::Page` title, description and eyebrow per instance.** The page now
  reads `#title`, `#description` and `#eyebrow`, which default to the class
  macros, so one page class can render many records (`def title = @widget.name`)
  without an anonymous subclass per render. The `eyebrow`, `description` and
  `on_page` macros inherit from a parent page when unset. Pages using only the
  class macros render byte-identically. (#95)

## [1.2.1] — 2026-09-30

### Changed

- **daisyui 2.x is allowed.** The dependency is now `>= 1.2, < 3`. 1.2.0 was
  tagged but never reached RubyGems (its release run failed a stale spec), so
  1.2.1 is the first published 1.2 release.

## [1.2.0] — 2026-09-30 (tagged; never published to RubyGems)

### Upgrading from 1.1

```bash
bundle update docs-kit
bin/rails g docs_kit:install --sync   # applies the 1.2 migration, prints what it can't
bun install && bun run build:css
bundle exec rspec
```

- **Ruby 3.3 or newer is required.** docs-kit 1.2 won't install on 3.2. Move
  `.ruby-version` and the Dockerfile's `ARG RUBY_VERSION` first (`--sync` warns
  about either one if it's still below 3.3).
- **`--sync` raises the toolchain it scaffolded.** In a Dockerfile that still
  carries docs-kit's old `ARG BUN_VERSION=1.3.2`, it bumps that to 1.4.2. In
  `package.json`, it raises docs-kit's old `tailwindcss` / `@tailwindcss/cli
  ^4.1.18` and `daisyui ^5.6.0` floors to `^4.3.3` / `^5.7.47`. Values you
  picked yourself are never rewritten: an older one is printed as a warning,
  and a newer one is left alone. Review the result with `git diff`.
- **Deploys pick up Node 24 actions and `ubuntu-26.04` automatically** when your
  `deploy-docs.yml` calls `zoolutions/docs-kit/.github/workflows/deploy.yml@main`
  (what `docs-kit new` scaffolds). `--sync` warns about a caller pinned to a tag
  or SHA; move the pin forward.
- **Untrack `app/assets/stylesheets/tailwind.sources.css`** if it's committed:
  `git rm --cached app/assets/stylesheets/tailwind.sources.css`. The generator
  now gitignores it; `--sync` reminds you when it's still tracked.

### Removed

- **Ruby 3.2 support.** `required_ruby_version` is now `>= 3.3` (3.2 reached
  end of life in March 2026), and CI no longer tests it.

### Changed

- **The reusable deploy workflow runs on Node 24 actions.** `deploy.yml` now
  uses `actions/checkout@v7`, `docker/setup-buildx-action@v4`,
  `docker/login-action@v4`, `docker/build-push-action@v7` and
  `webfactory/ssh-agent@v0.10.0`, clearing the Node 20 deprecation warning for
  every site that calls it. Its jobs run on `ubuntu-26.04` (ahead of the
  `ubuntu-latest` migration).
- **`docs_kit:install` scaffolds current toolchain floors.** The `package.json`
  stub requires `tailwindcss`/`@tailwindcss/cli` `^4.3.3` and `daisyui`
  `^5.7.47` (a spec keeps them in lockstep with the gem's own docs site), and
  the generated `Dockerfile` installs Bun 1.4.2 (and falls back to Ruby 3.4.11
  when the host Ruby version can't be read).
- **`docs_kit:install` gitignores the generated `tailwind.sources.css`.**
  `bin/build-css` rewrites it on every build with machine-specific gem paths, so
  a committed copy only churns. `--sync` adds the `.gitignore` entry and warns
  when the file is still tracked. (#72)
- **`--sync` runs its first release migration** (1.1 → 1.2, above). The
  migration registry no longer ships empty.

### Fixed

- **`docs_kit:page` injected the registry line once per group.** In a registry
  laid out as blank-line-separated groups (the layout `docs_kit:install`
  produces), the "page line not followed by a page line" Regexp anchor matched
  the end of *every* group and Thor's `inject_into_file` replaced every match.
  The anchor is now the file's last `page` line as a String, so one run adds
  exactly one line, at the end of the last group.

### Added

- **`DocsUI::Code` infers the language from `filename:`.**
  `DocsUI::Code(<<~YAML, filename: "config/deploy.yml")` now highlights as YAML
  instead of Ruby: with no `lexer:`, the lexer is guessed from Rouge's filename
  globs (`*.yml` → yaml, `Dockerfile` → docker, `*.sh` → shell, …). An explicit
  `lexer:` still wins, and a block with neither (or an unguessable filename)
  stays Ruby, so existing output is unchanged.

## [1.1.1] — 2026-08-27

### Fixed

- **`/llms.txt` sends a public max-age** (`expires_in 300, public: true`), so
  shared caches such as dash-proxy can store it; ETag revalidation is
  unchanged. (#75)

## [1.1.0] — 2026-08-27

### Added

- **Docs versions foundation.** `c.versions` (`DocsKit::DocVersion`),
  `c.repo_url` and `c.snapshots_path`, a request-scoped version
  (`DocsKit::Scope`) and a snapshot content source. A site that configures no
  versions renders unchanged. (#67)

### Changed

- **The reusable deploy workflow uses dash 4.** `deploy.yml` installs
  `dash ~> 4.0` and runs `dash doctor` before deploying; the registry secret is
  now `DASH_REGISTRY_PASSWORD` (`KAMAL_REGISTRY_PASSWORD` is still exported),
  and the `docs-kit new` deploy template turns on dash-proxy compression,
  caching and security headers. (#74)

### Fixed

- **Repointed at the `zoolutions` org.** The reusable deploy workflow, the
  `docs-kit new` and install templates, the README and the gemspec metadata
  now reference `zoolutions/docs-kit` (reusable-workflow `uses:` refs don't
  follow the repo move's redirect). (#70)

## [1.0.8] — 2026-08-04

### Added

- **`c.brand_logo`.** A config-driven brand mark (`svg:`, `paths:`, `markup:`,
  `file:` or `src:`) rendered by the new `DocsUI::Logo` in the topbar and
  sidebar brand links, falling back to `c.brand`; `c.landing.logo` accepts the
  same forms. `c.topbar_brand = :mobile_only` hides the topbar copy where the
  sidebar brand is already visible. (#68)

### Changed

- **The sidebar's top-level heading is flattened.** With one nav heading it
  is no longer rendered; with several, each is a static `menu-title` label and
  only subgroups collapse. The landing doc index follows the same rule. (#66)

## [1.0.7] — 2026-08-03

### Added

- **Version-aware `--sync` migrations.** Install and `--sync` stamp the
  initializer with `# docs-kit synced: vX.Y.Z`, and `--sync` runs the ordered
  migrations between that version and the gem's, printing what it can't
  automate. The migration registry ships empty in 1.0.x. (#56)
- **Two homes: `c.app_link`.** An opt-in `c.app_link = { href:, label: }`
  renders a topbar link back to the hosting app, and the page masthead's link
  now follows `c.brand_href` instead of the host's `root_path` and reads
  "← Docs home". (#63)

## [1.0.6] — 2026-07-04

### Added

- **`DocsUI::Landing` hero logo (`c.landing.logo`).** The landing hero now takes
  an optional brand mark above the eyebrow, in two forms: an inline single-path
  SVG (`{ svg: "<path d>", viewbox:, label: }`, rendered with `fill: currentColor`
  so it adapts to the theme) or an image (`{ src:, alt: }`, resolved through the
  site's asset pipeline). nil (the default) omits it, so it's backwards-compatible.
  This closes the gap a mounted docs app hit — a hero with no way to show the
  product's own logo — the first consumer to try `DocsUI::Landing` on a real site.

## [1.0.5] — 2026-07-04

### Added

- **`DocsUI::Landing` — a config-driven marketing landing page.** Every consuming
  site (and this dogfood site) was hand-rolling a home page; now render
  `DocsUI::Landing` and drive it from a new `c.landing` config block
  (`DocsKit::LandingConfig`): a hero (`eyebrow`, `title` — wrap a run in
  `**double asterisks**` to accent it in the primary color, `lead`, an optional
  `install` code snippet, and `ctas`), a `features` card grid, and a
  registry-grouped documentation index built from `nav_groups` (so it never drifts
  from the authored pages). Every field is optional — with an empty `c.landing` it
  still renders a minimal hero (brand + doc index), never a broken page — and its
  `.md`/`.text` twin works like any page. The install generator's `landings#show`
  now renders it and the initializer documents `c.landing`. This is the first
  landing pattern proven on a **mounted** docs app (a docs section inside a larger
  Rails app whose `/` is already taken), contributed back from that use case.

## [1.0.4] — 2026-07-04

### Changed

- **rouge 5 is allowed.** The dependency is now `>= 4.0, < 6`; the `< 5` cap
  was downgrading sites already on rouge 5. (#54)

### Fixed

- **`docs_kit:install --sync` no longer re-injects the commented `/mcp` route
  scaffold** into a site that already draws live MCP routes. (#53)

## [1.0.3] — 2026-07-04

### Added

- **`docs_kit:install` templates a lean multi-stage `Dockerfile` and a
  `.dockerignore`.** The `Dockerfile` is site-owned (skipped if present) and
  carries a `# docs-kit Dockerfile vX.Y.Z` marker that `--sync` warns about
  when it is older than the gem; `docs-kit new` uses the same template. (#52)

## [1.0.2] — 2026-07-03

### Fixed

- **SEO `og:image` 404.** The og:image tag pointed at the raw config path
  (`https://site/og/og.png`), which isn't a served URL — Propshaft serves the
  digested asset under `/assets`. A relative `og_image` is now resolved through
  the site's asset pipeline (`image_url`) to the digested `/assets/og/og-<digest>.png`
  URL, and the image is treated as **site content**: the gem ships none,
  `c.seo.og_image` defaults to **nil** (unset → no og:image tag, never a 404), and
  the `docs_kit:og` task writes into the *site's* `app/assets/images/`. Added a
  booted-app integration test in the dogfood site
  (`docs/test/integration/seo_meta_tags_test.rb`) that asserts og:image resolves
  to a `/assets` URL that actually returns 200 — the coverage isolated component
  specs can't provide.

## [1.0.1] — 2026-07-03

### Added

- **SEO + social sharing.** Every page now emits a complete SEO `<head>` —
  meta description, Open Graph, Twitter Card, canonical, favicon, robots, and
  theme-color — via the new `DocsUI::MetaTags` component, driven entirely by a
  new `c.seo` config block (`DocsKit::SeoConfig`). Pages carry an authorable
  `description "..."` (falling back to the page's `#lead`). The social-share image
  is site content (not shipped by the gem): the `docs_kit:og` rake task screenshots
  a site's OWN landing page into its `app/assets/images/og/` (host-side headless
  browser; never a gem runtime dependency), and `c.seo.og_image` points at it.
  Backwards-compatible: a site that sets no `c.seo` renders a valid minimal card
  and its `<head>` is a strict superset of before. The install generator documents
  `c.seo` and installs the task; `docs-kit new` reminds the owner to run it. (#48)

## [1.0.0] — 2026-07-03

### Added

- Release tooling matching the sibling gems (daisyui/phlex-reactive/pgbus): a
  `rake release[X.Y.Z]` task (version bump → lockfile update → build-verify →
  commit → push → GitHub Release; `pre`/`force` supported, `main`-only, clean-tree
  guard) and `.github/workflows/release.yml`, which on `release: published` runs
  the suite, content-checks the built gem, signs it with Sigstore, and publishes
  to RubyGems over **OIDC trusted publishing** (no stored API token). See the
  README "Releasing (maintainers)" section for the one-time trusted-publisher +
  `rubygems` environment setup.
- Initial extraction of the shared docs-site chrome into `docs-kit`.
- `Docs::*` Phlex component kit: `Shell` (full-document drawer layout), `Sidebar`
  (config-driven nav), `ThemeSwitcher`, `Icon`, `Code` (Rouge + inline theme),
  `Page`, `Header`, `Section`, `Prose`, `Callout`, `Example` (source extraction).
- `DocsKit.configure` for per-site brand, themes, nav, version badge, stylesheets,
  and code theme.
- `DocsKit::Registry` mixin for in-memory docs registries (slug/title/group +
  `all`/`from_slug`/`grouped` + the "authored" filter).
- `DocsKit::NavItem` value object consumed by the sidebar.
- `DocsKit::Controller#render_page` and a Rails engine that wires it.
- Custom RuboCop cops shipped from the gem (`require: docs_kit/rubocop` +
  `inherit_gem: { docs-kit: config/rubocop/docs_kit.yml }`, wired automatically by
  the install generator): `DocsKit/RenderComponentPreferred` (prefer the Phlex-kit
  helper form `DocsUI::Code(...)` over `render DocsUI::Code.new(...)`) and
  `DocsKit/EscapedInterpolationInHeredoc` (steer `\#{...}` escapes in a
  double-quoted heredoc to a single-quoted delimiter). RuboCop stays a
  development-time dependency of the host — never a runtime dependency.
- `rails g docs_kit:install --sync`: the sanctioned upgrade path for an existing
  site. Runs only the additive/wiring steps (routes, initializer hint,
  importmap/Stimulus registration, AGENTS.md, `.rubocop.yml`) — never
  re-scaffolds site-owned content (the `Doc` registry, pages, the themed CSS
  build) — and prints a conservative drift checklist (a hand-written
  `render_page`, a dead `IconHelper`) it warns about but never auto-deletes. See
  the README "Keeping a site in sync" section.

### Fixed

- `rails g docs_kit:install` is now fully idempotent, making re-running it the
  safe upgrade path: `create_initializer` no longer clobbers a site's edited
  `config/initializers/docs_kit.rb` (it skips + hints at the template for a
  diff), and `add_routes` no longer duplicates a route the site already drew when
  it was written in a different style (single vs double quotes, `to:` vs `=>`).
