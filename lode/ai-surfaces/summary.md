# AI surfaces — the Markdown twin, llms.txt, search, MCP

Four consumer-facing surfaces, all derived from the pages themselves so none can drift from the docs. `DocsKit::LlmsText.pages` is the shared enumeration seam and `DocsKit::MarkdownExport` is the shared rendering seam; every surface below is a thin skin over those two.

## `DocsKit::MarkdownExport` — the twin

`markdown_export.rb` plus `blocks.rb`, `inline.rb`, `table.rb`. It derives GFM **from the page's own rendered HTML**, not from a second authored source — so Phlex markup, `md` islands and raw tags in `Prose` all convert identically, and the twin can never drift from what the page shows.

The pipeline: render the view → `Nokogiri::HTML5.fragment` → `at_css("#docs-content")` → remove everything matching `[data-md-skip], script, style` → walk the subtree. Two render-time hints carry the cases HTML alone can't express: `data-md-lang` (stamped by `DocsUI::Code`) becomes a fenced block's language, and `data-md-callout` (stamped by `DocsUI::Callout`) becomes a `> **Tip:**` blockquote, labelled from `CALLOUT_LABELS` (note / tip / warning).

`#to_md` returns `""` when there is no `#docs-content` region — a page that isn't the docs chrome exports nothing rather than exporting the wrong thing; the HTML route is untouched either way.

`#render_html` picks one of three paths, in order (`markdown_export.rb:77-85`): a view whose `#call` accepts a `view_context:` keyword gets it; else a Phlex component with a view context is rendered through Rails (`@view_context.render(@view)`); else a bare `#call`. `#absolutize` rewrites relative hrefs against `base_url` and leaves absolute, protocol-relative, and `#`/`mailto:` URLs alone.

## `DocsKit::LlmsText` and `LlmsController` — `/llms.txt`, `/llms-full.txt`

`LlmsText` is a pure `module_function` text builder with no Rails. `.index` (`llms_text.rb:35-47`) emits `# brand`, an optional `> tagline` blockquote, one `## group` block per nav group as a tight bullet list of `.md` links, and — last, and only when `config.mcp_enabled?` — an `## MCP` block advertising the endpoint. `.full` joins `# title` + body pairs with a `---` rule.

`.pages` (`llms_text.rb:68-73`) is **the** enumeration seam: resolve the version from the argument, else `Scope.version`, else `config.current_version`; an archived version enumerates its snapshot, anything else flattens `config.nav_registries` to entries with a resolvable `view_class`. `.renderable_for` (`87-89`) is the matching render seam, with a `respond_to?(:renderable)` fallback to `view_class.new` for a site's older custom registry class.

`DocsKit::LlmsController` threads the Rails view context and nothing else. `#full` renders each page's twin through `MarkdownExport` and hands the pairs to `LlmsText.full`. Caching is `expires_in LLMS_MAX_AGE (300), public: true` plus `stale?(etag: [DocsKit::VERSION, body], public: true)` — the max-age matters because `public` alone is not storable under RFC 9111, so a shared cache would skip the response; the etag still revalidates inside the window.

## `DocsKit::SearchIndex` and `SearchController` — `/docs/search`

The index is built **per request** from the same Markdown twins `llms-full.txt` serves, so search cannot drift from the pages. There is no external service, no build step, no second registry.

`SearchIndex.new(triples)` takes `[[page_title, page_href, markdown], …]` and splits each twin on level-2 ATX headings. `#split_sections` (`search_index.rb:104-120`) scans line by line and toggles an in-fence flag on ``` / ~~~ so a `## ` inside a code block stays body text — the rendered page never ids it, so a section entry there would carry a dead anchor. Text before the first heading becomes a page-intro entry; a page with neither still gets one entry so its title is searchable.

Scoring is plain Ruby: tokens are whitespace-split and lowercased, **every** token must match somewhere (AND), and each token scores the heaviest field it hit — `TITLE_WEIGHT` 100 > `HEADING_WEIGHT` 10 > `BODY_WEIGHT` 1. The page title is a searchable field **only on the page-intro entry**, because a title token matches every section of a page equally and weighting each one would flood the results with near-identical rows. Results sort by `[-score, page_title, section_title]` and cap at `MAX_RESULTS` (20). No fuzzy matching.

`SearchController#index` answers both formats off the same index: `html` renders `DocsUI::SearchResults` inside a `Shell` (the JS-off path the topbar form submits to), `json` serves the palette's debounced fetch.

## `DocsKit::McpTools`, `McpServer`, `McpController` — `POST /mcp`

`McpTools` is the pure core: `list_pages`, `get_page(slug:)`, `search_docs(query:)`, all over the same registry, twins and index. Zero `mcp`-gem dependency and zero JSON-RPC, so the whole consumption story is unit-testable without the SDK.

`McpServer.build` wraps them into an `MCP::Server`, returning **nil** when the gem isn't loadable. `base_url` and `view_context` ride in the SDK's `server_context` so the tools render twins through Rails and absolutize URLs — the same seam `LlmsController#full` uses.

`McpController#create` heads 404 unless `mcp_enabled?` and again unless the server builds, then delegates the entire protocol to `server.handle_json(request.body.read)`. That returns an already-serialised JSON string, so it is rendered as `body:` with an explicit content type — `render json:` would re-encode the string and corrupt the JSON-RPC envelope. GET and DELETE are 405: the endpoint is read-only and stateless, with no SSE stream and no session to terminate.

## `DocsKit::OpenApi` — the spec bridge

`open_api.rb` plus `document.rb`, `operation.rb`, `schema.rb`. Loads an OpenAPI 3.x spec (file path or parsed Hash; YAML via Psych, JSON via the stdlib — no parser dependency) into a narrow gem-owned model exposing only what the render targets consume: `#body_rows` for a `FieldTable`, `#error_rows` for an `ErrorTable`, `#success_example` for a `JsonResponse`. `OperationNotFound` lists the available operationIds so a typo is diagnosable at the call site. `DocsUI::OpenApiOperation` renders one operation through the kit.

## Wiring

All three gem controllers subclass `ActionController::Base` directly, include `DocsKit::Scoping`, name their config reader `#docs_config`, and are routed by the **host** — the engine draws no routes. `InstallGenerator#add_routes` draws the llms and search routes live and the MCP pair commented out, because MCP needs the optional gem.

## Related

- `../registry-and-versions/summary.md` — what `.pages` enumerates
- `../components/summary.md` — `#docs-content`, `data-md-skip`, `data-md-lang`
- `../install-path/summary.md` — the routes the generator draws
