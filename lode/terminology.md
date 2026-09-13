# Terminology

The words this repository uses, with the file that defines each.

- **chrome** — everything around a page's authored content: shell, topbar, sidebar, theme switcher, masthead. Shipped by the gem as `DocsUI::` Phlex components (`app/components/docs_ui/`, 30 component classes plus the `PageHelpers` module).
- **the kit / `DocsUI`** — the `DocsUI` module, extended with `Phlex::Kit` in `lib/docs_kit.rb`, so every component constant is also a bare callable: `DocsUI::Code(src)` == `render DocsUI::Code.new(src)`. Named `DocsUI`, not `Docs`, so it never collides with a host app's `Views::Docs` page namespace.
- **consuming site / docs site** — a Rails app that bundles the gem and calls `DocsKit.configure`. This repo's `docs/` directory is one (the dogfood site), depending on the gem via `path: ".."`.
- **registry** — an in-memory list of a site's pages. A site class `extend DocsKit::Registry` and declares pages; the mixin supplies `.all` / `.from_slug` / `.grouped` / `.nav_items` (`lib/docs_kit/registry.rb`).
- **the `page` DSL (v2)** — `page "Installation", group: "Guide"`, one line per page, slug and view class derived from the title (`Registry#page`, `registry.rb:65-75`). The older form is the hash `entries [...]` API; a registry uses one style, and mixing them raises `Registry::Error`.
- **authored page** — a registry entry whose `#view_class` resolves to a real constant (`Registry::Entry#view_class`, `registry.rb:145-149`). `nav_items`, `llms.txt`, search and MCP all filter to authored pages, so a declared-but-unwritten page is never linked.
- **Markdown twin** — the GFM rendering of a page derived from the page's own rendered HTML, not from a second source (`DocsKit::MarkdownExport`). `GET /docs/x.md` returns it; `/llms-full.txt` concatenates them; the search index is built from them.
- **`#docs-content`** — the `div` id the Shell stamps on its content column (`shell.rb:142`). It is the extraction anchor for the Markdown twin, which is why the topbar, sidebar and TOC render outside it.
- **`data-md-skip`** — the attribute that drops an element from the Markdown twin (`MarkdownExport::DROP_SELECTOR`). `DocsUI::Page` puts its "← Docs home" nav inside it.
- **scope** — the request-scoped content axis: which documentation version this render serves (`DocsKit::Scope`, backed by `Thread.current`, deliberately not `CurrentAttributes` so bare Phlex specs can set one without Rails). `Scope.locale` is reserved and always nil today.
- **snapshot** — a committed Markdown freeze of one archived documentation version, read back as the registry duck type (`DocsKit::Snapshot`), so an archived version renders through today's chrome.
- **current version / archived version** — the version serving unprefixed at `/docs` versus one serving at `/<id>/docs` (`DocVersion#path_prefix`, `doc_version.rb:55-57`). `versioning_enabled?` needs at least two configured versions.
- **`--sync`** — the install generator's upgrade mode: re-run the additive wiring, scaffold no site-owned content, report drift (`InstallGenerator`'s `:sync` class option).
- **drift** — a hand-written artefact in a site that the gem now provides, detected but never rewritten by `DocsKit::Generators::SyncReport`.
- **synced stamp** — the inert `# docs-kit synced: vX.Y.Z` comment the generator writes at the top of `config/initializers/docs_kit.rb`, so the next `--sync` knows which migrations to run (`SYNCED_STAMP_RE`, `install_generator.rb:56`).
- **`tailwind.sources.css`** — the generated file `bin/build-css` writes with `@source` globs pointing at the resolved `daisyui` and `docs-kit` gem paths, imported by `application.tailwind.css`. Generated per environment, so it is gitignored in the sites that have it.
- **dash** — the deploy tool the reusable workflow drives (`.github/workflows/deploy.yml`): build with buildx, push to GHCR, deploy with `--skip-push` behind a Cloudflare Tunnel and dash-proxy.
