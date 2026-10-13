# frozen_string_literal: true

module Views
  module Docs
    module Pages
      # The canonical knob reference: DocsKit.configure, the complete options
      # table grouped by concern, and the two nav paths (registries vs. lambda).
      class Configuration < DocsUI::Page
        title "Configuration"
        eyebrow "Getting started"

        def lead = "One initializer drives the shared chrome. Everything that differs between two sites — brand, themes, nav, search, API examples — is config; the Shell, Sidebar, and ThemeSwitcher are identical everywhere."

        def content
          configure_section
          brand_themes_section
          nav_section
          code_section
          search_section
          api_section
          ai_section
        end

        private

        def configure_section
          DocsUI::Section("DocsKit.configure", description: "Set it once; the shared chrome reads it everywhere.") do
            prose do
              p do
                plain "Call "
                code { "DocsKit.configure" }
                plain " with a block and set "
                code { "c.<knob>" }
                plain " on the yielded "
                code { "DocsKit::Configuration" }
                plain " singleton. Read any value back with "
                code { "DocsKit.configuration" }
                plain ". Every knob has a sensible default, so a brand-new site works with an empty block."
              end
              p do
                plain "Configure inside "
                code { "config.to_prepare" }
                plain " so the block re-runs on every code reload — that keeps the derived nav pointing at the current registry in development."
              end
            end
            DocsUI::Code(<<~RUBY, filename: "config/initializers/docs_kit.rb")
              Rails.application.config.to_prepare do
                DocsKit.configure do |c|
                  c.brand          = "Acme Docs"
                  c.tagline        = "Everything the Acme API can do."
                  c.themes         = %w[dark light dracula night]
                  c.default_theme  = "dark"
                  c.version_badge  = -> { "v\#{Acme::VERSION}" }

                  c.nav_registries = { "Docs" => Doc, "API" => ApiDoc }
                end
              end
            RUBY
          end
        end

        def brand_themes_section
          DocsUI::Section("Brand & themes", description: "Identity, the topbar, the <title>, and the theme switcher.") do
            prose do
              p do
                plain "The one required-ish knob is "
                code { "brand" }
                plain " — it names the topbar and sidebar header, and is the fallback for both "
                code { "title_suffix" }
                plain " and "
                code { "nav_storage_key" }
                plain ", so setting a String brand alone gets you sensible page titles and per-site localStorage namespacing. A callable brand (one per host or tenant) is resolved on every render and needs an explicit "
                code { "nav_storage_key" }
                plain " — the localStorage key must be stable per browser, not per request."
              end
              p do
                plain "The theme list is the contract with your CSS: the values in "
                code { "themes" }
                plain " MUST match the daisyUI "
                code { %(@plugin "daisyui" { themes: ... }) }
                plain " block in your Tailwind entry. A theme offered here that the build never generated is a dead switcher entry. See the "
                a(href: "/docs/styling") { "Styling & CSS" }
                plain " page for wiring that up."
              end
            end
            render DocsUI::PropTable.new(
              [
                [ "brand", "String or callable", '"Docs"', "Topbar + sidebar heading. Fallback for title_suffix and nav_storage_key. A callable is invoked per render (one brand per host/tenant) and requires an explicit nav_storage_key." ],
                [ "tagline", "String, nil", "nil", "One-line summary; rendered as the llms.txt blockquote. AI-index only — the chrome never shows it." ],
                [ "brand_href", "String", '"/"', "Where the topbar brand link points (e.g. \"/docs\" for a subpath site)." ],
                [ "title_suffix", "String or callable", "= brand", %(Appended to the page <title> ("Installation · Acme"). A callable is invoked per render; unset follows the resolved brand.) ],
                [ "themes", "Array", "%w[dark light]", "ThemeSwitcher options; must match the daisyUI @plugin themes: block." ],
                [ "default_theme", "String", "= themes.first", "The data-theme applied on first paint. Writer only; reader falls back to themes.first." ],
                [ "version_badge", "String or callable", "nil", "Short badge string for the sidebar header. A callable is invoked; a plain String is used as-is; nil = no badge." ],
                [ "stylesheets", "Array", "%w[application]", "Stylesheet logical names linked in <head>, in order." ],
                [ "default_group_icon", "String", '"file-text"', "lucide icon for a nav group with no explicit icon." ],
                [ "icon_library", "String, nil", '"lucide"', "The RailsIcons library the chrome renders its own icons from. nil defers to the host default." ],
                [ "nav_storage_key", "String", "= brand slug", "Namespaces the sidebar localStorage (collapse state) so two sites on one origin don't collide. Required when brand is a callable. Writer only." ],
                [ "page_markdown_action", "Boolean", "true", "Show the \"Markdown\" masthead action (a link to the .md twin). false hides it; the .md route still works." ],
                [ "on_page_default", ":panel | :toggle | :sidebar | false", ":panel", "Default auto-TOC placement when a page doesn't set its own on_page:." ]
              ]
            )
            DocsUI::Callout(:note) do
              plain "The version badge accepts a "
              strong { "String OR a callable" }
              plain " — "
              code { %(c.version_badge = "v1.2") }
              plain " and "
              code { %(c.version_badge = -> { "v\#{Acme::VERSION}" }) }
              plain " both render. A lambda is handy when the version lives in a constant that loads after the initializer."
            end
          end
        end

        def nav_section
          DocsUI::Section("The sidebar nav", description: "Registries are the canonical path; a nav lambda is the escape hatch.") do
            prose do
              p do
                plain "The common case is "
                code { "nav_registries" }
                plain " — an ordered "
                code { '{ "Heading" => registry_class }' }
                plain " map. Each registry answers "
                code { ".nav_items" }
                plain " (a "
                code { "DocsKit::Registry" }
                plain " method returning "
                code { "{ group => [NavItem] }" }
                plain "), and the whole sidebar derives from it with zero site nav code. A heading whose registry has no authored pages is dropped, so no empty group renders. The registry's groups are the top level of the menu; the heading itself only renders — as a static label — when several headings are registered, so a one-registry site gets no redundant top fold."
              end
            end
            DocsUI::Code(<<~RUBY, filename: "config/initializers/docs_kit.rb")
              c.nav_registries = { "Docs" => Doc, "API" => ApiDoc }
            RUBY
            prose do
              p do
                plain "Reach for the explicit "
                code { "nav" }
                plain " lambda only for bespoke nav — interleaving multiple registries, or hand-built subgroups. It must return an ordered "
                code { '{ "Heading" => { "Subgroup" => [items] } }' }
                plain " Hash where each item responds to "
                code { "#href" }
                plain ", "
                code { "#label" }
                plain ", and optional "
                code { "#icon" }
                plain "."
              end
            end
            DocsUI::Code(<<~RUBY)
              c.nav = lambda do
                grouped = Doc.all.group_by(&:group).transform_values do |docs|
                  docs.map { |d| DocsKit::NavItem.new(href: "/docs/\#{d.slug}", label: d.title) }
                end
                {
                  "Getting started" => { "Basics" => grouped.fetch("basics", []) },
                  "Reference"       => { "API" => grouped.fetch("api", []) }
                }
              end
            RUBY
            render DocsUI::PropTable.new(
              [
                [ "nav_registries", "Hash", "{}", %({ "Heading" => registry_class }; each registry answers .nav_items. The canonical, zero-code nav path.) ],
                [ "nav", "callable", "-> {}", "Explicit nav lambda; wins over nav_registries when assigned. For bespoke interleaved nav only." ]
              ]
            )
            DocsUI::Callout(:warning) do
              plain "Assigning "
              code { "nav" }
              plain " to "
              strong { "any" }
              plain " value — even "
              code { "-> { {} }" }
              plain " — marks it explicit and stops derivation from "
              code { "nav_registries" }
              plain ". If you set an empty nav lambda while relying on registries, you get an empty sidebar. Leave "
              code { "nav" }
              plain " unset unless you truly need the escape hatch."
            end
          end
        end

        def code_section
          DocsUI::Section("Code highlighting", description: "The Rouge themes and the lexer/label maps DocsUI::Code and Example read.") do
            prose do
              p do
                plain "Syntax highlighting is inline Rouge CSS. "
                code { "code_theme" }
                plain " is the base (light) theme, emitted un-scoped so it applies everywhere. Set "
                code { "code_theme_dark" }
                plain " and docs-kit additionally emits that theme's CSS scoped under each shipped "
                strong { "dark" }
                plain " theme — CSS-only, no JS, no flash. Which themes count as dark comes from "
                code { "dark_themes" }
                plain " (defaults to the 13 built-in daisyUI dark themes), intersected with your "
                code { "themes" }
                plain "."
              end
              p do
                plain "The lexer and label maps are merged "
                strong { "over" }
                plain " the built-ins, so you only add or override. Any of Rouge's ~200 languages already works by its own name — see the "
                a(href: "/docs/languages") { "Code languages" }
                plain " page."
              end
            end
            render DocsUI::PropTable.new(
              [
                [ "code_theme", "String or Class", '"Rouge::Themes::Monokai"', "The base (light) Rouge theme for inline highlight CSS. An unresolvable name degrades to the default." ],
                [ "code_theme_dark", "String, Class, nil", "nil", "Optional second Rouge theme, scoped under each shipped dark theme. nil = single-theme behavior." ],
                [ "dark_themes", "Array", "13 built-in dark themes", "Which theme names are treated as dark for code_theme_dark scoping. Override for custom dark themes." ],
                [ "code_lexer_aliases", "Hash", "{}", %(Friendly-name → Rouge lexer aliases, merged over built-ins ({ dockerfile: "docker" }).) ],
                [ "code_lexer_fallback", "String", '"plaintext"', "The lexer used when a language can't be resolved (no highlighting, never raises)." ],
                [ "code_language_labels", "Hash", "{}", %(Human labels for Example language tabs, merged over built-ins ({ elixir: "Elixir" }).) ]
              ]
            )
          end
        end

        def search_section
          DocsUI::Section("Search", description: "The topbar search form and the ⌘K command palette.") do
            prose do
              p do
                plain "Search is on by default. The Shell renders the affordance when "
                code { "search" }
                plain " is true "
                strong { "and" }
                plain " "
                code { "search_path" }
                plain " is non-blank (the gate is "
                code { "#search_enabled?" }
                plain "). Blank the path to disable the form without touching the toggle. The keyboard shortcuts that open the palette are configurable — "
                code { "mod" }
                plain " is the platform modifier (⌘ on mac, Ctrl elsewhere), so one entry works on every OS."
              end
              p do
                plain "See the "
                a(href: "/docs/search") { "Search" }
                plain " page for how the index is built and served."
              end
            end
            render DocsUI::PropTable.new(
              [
                [ "search", "Boolean", "true", "Whether the topbar renders the search form + palette markup." ],
                [ "search_path", "String", '"/docs/search"', "Where the form submits (GET ?q=) and the palette fetches .json. Blank to disable." ],
                [ "search_shortcuts", "Array", "%w[/ mod+k]", "Keyboard shortcuts that open the palette. Writer only; read the parsed form via #search_shortcuts." ]
              ]
            )
          end
        end

        def api_section
          DocsUI::Section("API examples", description: "The base URL, auth line, and client tabs DocsUI::RequestExample renders.") do
            prose do
              p do
                plain "The API-docs kit turns one request declaration into a tab per client. "
                code { "api_base_url" }
                plain " is prefixed onto each snippet's path; "
                code { "api_auth_header" }
                plain " is an optional example auth line merged into every snippet. "
                code { "api_clients" }
                plain " overrides or extends the four shipped defaults ("
                code { "curl" }
                plain ", "
                code { "javascript" }
                plain ", "
                code { "ruby" }
                plain ", "
                code { "python" }
                plain ") — reusing a token replaces that client, a new token appends a tab."
              end
              p do
                plain "The "
                a(href: "/docs/api") { "API reference" }
                plain " page shows the kit rendered live."
              end
            end
            DocsUI::Code(<<~RUBY, filename: "config/initializers/docs_kit.rb")
              c.api_base_url   = "https://api.acme.com"
              c.api_auth_header = "Authorization: Bearer sk_live_..."
              c.api_clients = {
                cli: DocsKit::ApiClient.new(
                  label: "CLI", lexer: :shell,
                  template: ->(req) { "acme \#{req.http_method.downcase} \#{req.path}" }
                )
              }
            RUBY
            render DocsUI::PropTable.new(
              [
                [ "api_base_url", "String", '"https://api.example.com"', "Prefixed onto each RequestExample path so snippets point at a real host." ],
                [ "api_auth_header", "String, nil", "nil", "Example Authorization header line merged into every snippet. nil = no auth line." ],
                [ "api_clients", "Hash", "4 shipped defaults", "{ token => DocsKit::ApiClient } merged over curl/javascript/ruby/python. Writer only; read the merged map via #api_clients." ]
              ]
            )
          end
        end

        def ai_section
          DocsUI::Section("AI & tooling", description: "The built-in MCP endpoint.") do
            prose do
              p do
                plain "docs-kit ships an optional read-only MCP endpoint ("
                code { "POST /mcp" }
                plain ", JSON-RPC exposing "
                code { "list_pages" }
                plain " / "
                code { "get_page" }
                plain " / "
                code { "search_docs" }
                plain " over the docs registry). "
                code { "mcp" }
                plain " is true by default, but the endpoint only turns on when the optional "
                code { "mcp" }
                plain " gem is "
                strong { "also" }
                plain " loadable and the host draws the route — gate on "
                code { "#mcp_enabled?" }
                plain ", not the raw toggle."
              end
              p do
                plain "See the "
                a(href: "/docs/ai") { "AI & agents" }
                plain " page for llms.txt, the .md twins, and the MCP server."
              end
            end
            render DocsUI::PropTable.new(
              [
                [ "mcp", "Boolean", "true", "Whether the built-in MCP endpoint is active. Actually gated by #mcp_enabled? (toggle AND the mcp gem loadable)." ]
              ]
            )
          end
        end
      end
    end
  end
end
