# frozen_string_literal: true

module Views
  module Docs
    module Pages
      # Documents AND demonstrates the DocsUI kit — each section renders the real
      # component live (where sensible), next to the code that produced it and a
      # table of its args.
      class Components < DocsUI::Page
        title "Components"
        eyebrow "Reference"

        def lead = "Every DocsUI component — shown live where it makes sense, with its calling code and args."

        def content
          shell_section
          page_section
          header_section
          section_section
          prose_section
          code_section
          example_section
          table_section
          endpoint_section
          request_example_section
          callout_section
          icon_section
          on_this_page_section
          sidebar_section
          theme_switcher_section
        end

        private

        # --- Document-level components (described, not rendered live) ---------

        def shell_section
          DocsUI::Section("Shell", description: "The whole HTML document you're looking at right now.") do
            prose do
              p do
                code { "DocsUI::Shell" }
                plain " is the top-level page: the topbar (brand + "
                code { "ThemeSwitcher" }
                plain "), the "
                code { "Sidebar" }
                plain ", the content column, and the auto TOC. It yields the page body. "
                code { "Page" }
                plain " renders it for you — you rarely construct it directly."
              end
            end
            DocsUI::Code(<<~RUBY)
              DocsUI::Shell(title: "My guide", on_page: :panel) do
                # page body
              end
            RUBY
            render DocsUI::PropTable.new(
              [
                [ "title", "String, nil", "nil", "Document + topbar title. Falls back to the site brand." ],
                [ "on_page", "Symbol, false", "false", "TOC placement — :panel / :toggle / :sidebar / false." ]
              ],
              headers: [ "Arg", "Type", "Default", "Description" ]
            )
          end
        end

        def page_section
          DocsUI::Section("Page", description: "The base class you subclass for every docs page — including this one.") do
            prose do
              p do
                plain "Subclass "
                code { "DocsUI::Page" }
                plain ", set "
                code { "title" }
                plain "/"
                code { "eyebrow" }
                plain " with the class-level DSL, and implement "
                code { "#content" }
                plain " (and optionally "
                code { "#lead" }
                plain "). The page wraps your content in the "
                code { "Shell" }
                plain " with a "
                code { "Header" }
                plain " masthead and auto TOC."
              end
            end
            DocsUI::Code(<<~RUBY)
              class Views::Docs::Pages::Guide < DocsUI::Page
                title   "My guide"
                eyebrow "Reference"
                on_page :toggle          # :panel | :toggle | :sidebar | false

                def lead = "One-sentence summary."
                def content = DocsUI::Section("Hello") { prose { p { "..." } } }
              end
            RUBY
            render DocsUI::PropTable.new(
              [
                [ "title", "String (class DSL)", "—", "Sets the document + masthead title." ],
                [ "eyebrow", "String (class DSL)", "nil", "Small kicker above the h1 (e.g. the group)." ],
                [ "on_page", "Symbol (class DSL)", "config default", "TOC placement — :panel / :toggle / :sidebar / false." ],
                [ "#lead", "instance method", "nil", "Muted summary paragraph under the h1." ],
                [ "#content", "instance method", "—", "The page body — call kit components here." ]
              ],
              headers: [ "Arg", "Type", "Default", "Description" ]
            )
          end
        end

        def header_section
          DocsUI::Section("Header", description: "The masthead: eyebrow + h1 + optional lead.") do
            prose do
              p do
                plain "The block at the top of this page — kicker, heading, summary — is a "
                code { "DocsUI::Header" }
                plain ". "
                code { "Page" }
                plain " builds it from your "
                code { "title" }
                plain "/"
                code { "eyebrow" }
                plain "/"
                code { "#lead" }
                plain ", so you seldom render it yourself."
              end
            end
            DocsUI::Code(<<~RUBY)
              DocsUI::Header("My guide", eyebrow: "Reference") do
                plain "An optional lead paragraph."
              end
            RUBY
            render DocsUI::PropTable.new(
              [
                [ "title", "String (positional)", "—", "The h1 text. Legacy title: kwarg still accepted." ],
                [ "eyebrow", "String, nil", "nil", "Small kicker above the h1." ],
                [ "block", "Phlex block", "nil", "Optional lead paragraph rendered under the h1." ]
              ],
              headers: [ "Arg", "Type", "Default", "Description" ]
            )
          end
        end

        # --- Content components (rendered live) -------------------------------

        def section_section
          DocsUI::Section("Section", description: "An anchored section wrapper — this description is its description: arg.") do
            prose do
              p do
                plain "Every block on this page is a "
                code { "DocsUI::Section" }
                plain ". It renders a "
                code { "<section id>" }
                plain " with an "
                code { "<h2>" }
                plain ", an optional muted "
                code { "description:" }
                plain " lead, then your block. The "
                code { "id" }
                plain " auto-slugs from the title (feeding the TOC), or pass "
                code { "id:" }
                plain " to override it."
              end
            end
            DocsUI::Code(<<~RUBY)
              DocsUI::Section("Getting started", id: "start", description: "Read me first.") do
                prose { p { "Section body." } }
              end
            RUBY
            render DocsUI::PropTable.new(
              [
                [ "title", "String", "—", "The h2 text; auto-slugs into the anchor id." ],
                [ "id", "String, nil", "slug of title", "Override the section anchor." ],
                [ "description", "String, callable, nil", "nil", "Muted lead paragraph under the h2." ]
              ],
              headers: [ "Arg", "Type", "Default", "Description" ]
            )
          end
        end

        def prose_section
          DocsUI::Section("Prose", description: "A typographic wrapper for hand-authored HTML.") do
            prose do
              p { "Prose gives hand-authored text a consistent reading rhythm without a typography plugin." }
              ul do
                li { "lists," }
                li { "inline code," }
                li { "links — all styled." }
              end
            end
            prose { p { "The call that produced the block above:" } }
            DocsUI::Code(<<~RUBY)
              prose do
                p { "Prose gives hand-authored text a consistent reading rhythm." }
                ul { li { "lists," }; li { "inline code," }; li { "links." } }
              end
            RUBY
            DocsUI::Callout(:tip) do
              plain "On a "
              code { "DocsUI::Page" }
              plain " use the lowercase "
              code { "prose do … end" }
              plain " helper — a method call, no parens needed. The kit form "
              code { "DocsUI::Prose() do … end" }
              plain " also works, but bare "
              code { "DocsUI::Prose do" }
              plain " is a SyntaxError, so it needs the empty "
              code { "()" }
              plain "."
            end
            render DocsUI::PropTable.new(
              [
                [ "block", "Phlex block", "—", "Hand-authored HTML — p, ul/li, code, strong, a, plain text." ]
              ],
              headers: [ "Arg", "Type", "Default", "Description" ]
            )
          end
        end

        def code_section
          DocsUI::Section("Code", description: "A Rouge-highlighted code block with an optional filename bar.") do
            DocsUI::Code(<<~RUBY, filename: "app/models/user.rb")
              class User < ApplicationRecord
                has_many :posts
              end
            RUBY
            prose { p { "The call that produced the block above:" } }
            DocsUI::Code(%(DocsUI::Code(source, lexer: :ruby, filename: "app/models/user.rb")))
            render DocsUI::PropTable.new(
              [
                [ "source", "String", "—", "The code to highlight." ],
                [ "lexer", "Symbol", "inferred", "Any Rouge language — :shell, :yaml, :erb, :python, :go, etc. Overrides the filename guess; ruby when neither is given." ],
                [ "filename", "String, nil", "nil", "Optional filename bar above the block. Also selects the language (*.yml → yaml, Dockerfile → docker, *.sh → shell)." ]
              ],
              headers: [ "Arg", "Type", "Default", "Description" ]
            )
          end
        end

        def example_section
          DocsUI::Section("Example", description: "Multi-language tabbed code with a sticky, global language choice.") do
            example do |ex|
              ex.code(:ruby, filename: "client.rb") do
                %(Anthropic::Client.new.messages.create(model: "claude-opus-4-8", messages: msgs))
              end
              ex.code(:python, filename: "client.py") do
                %(anthropic.Anthropic().messages.create(model="claude-opus-4-8", messages=msgs))
              end
            end
            prose { p { "The call that produced the tabs above:" } }
            DocsUI::Code(<<~RUBY)
              example do |ex|
                ex.code(:ruby, filename: "client.rb")   { ruby_source }
                ex.code(:python, filename: "client.py") { python_source }
              end
            RUBY
            render DocsUI::PropTable.new(
              [
                [ "block", "Phlex block", "—", "Yields an object with #code — one call per language." ],
                [ "ex.code lang", "Symbol", "—", "The Rouge language for this tab." ],
                [ "ex.code filename:", "String, nil", "nil", "Optional filename bar for this tab." ],
                [ "ex.code lexer:", "Symbol", "lang", "Override the Rouge lexer if it differs from the tab label." ]
              ],
              headers: [ "Arg", "Type", "Default", "Description" ]
            )
          end
        end

        def table_section
          DocsUI::Section("Table & PropTable", description: "Reference tables — generic headers+rows, and a name/type/default/description preset.") do
            prose do
              p do
                code { "DocsUI::Table" }
                plain " renders headers + rows in the kit's daisyUI look. A cell is a "
                code { "String" }
                plain " (plain, escaped), a "
                code { "[:code, \"x\"]" }
                plain " pair (inline "
                code { "<code>" }
                plain "), or a "
                code { "[:md, \"…\"]" }
                plain " pair (inline Markdown). "
                code { "DocsUI::PropTable" }
                plain " is the preset every args table on this page uses — the same shape, first column auto code-styled, default "
                code { "Option/Type/Default/Description" }
                plain " headers."
              end
            end
            DocsUI::Table(
              [ "Cell", "Renders as" ],
              [
                [ "brand", "plain, escaped text" ],
                [ [ :code, "%w[dark light]" ], "inline code" ],
                [ [ :md, "a **bold** note" ], "inline markdown" ]
              ]
            )
            prose { p { "The call that produced the table above:" } }
            DocsUI::Code(<<~RUBY)
              DocsUI::Table(
                [ "Cell", "Renders as" ],
                [
                  [ "brand", "plain, escaped text" ],
                  [ [ :code, "%w[dark light]" ], "inline code" ],
                  [ [ :md, "a **bold** note" ], "inline markdown" ]
                ]
              )
            RUBY
            DocsUI::Callout(:tip) do
              plain "Every args table on this page is a "
              code { "DocsUI::PropTable" }
              plain " — pass just the rows; the headers default to "
              code { "Option/Type/Default/Description" }
              plain " (override with "
              code { "headers:" }
              plain ")."
            end
            render DocsUI::PropTable.new(
              [
                [ "DocsUI::Table headers", "Array", "—", "Header labels — one per column." ],
                [ "DocsUI::Table rows", "Array", "—", "Rows; each a cell array (String / [:code, x] / [:md, …])." ],
                [ "DocsUI::PropTable rows", "Array", "—", "Rows; the first cell is auto-wrapped in <code>." ],
                [ "DocsUI::PropTable headers:", "Array", "Option/Type/Default/Description", "Override the header labels." ]
              ]
            )
          end
        end

        def endpoint_section
          DocsUI::Section(
            "Endpoint, FieldTable & ErrorTable",
            description: "The API-reference kit — a method+path line, a fields table, and an error table."
          ) do
            prose do
              p do
                code { "DocsUI::Endpoint" }
                plain " renders an HTTP method badge (coloured per verb) plus a monospace path, inline — so it drops straight into a "
                code { "Section" }
                plain " description. "
                code { "FieldTable" }
                plain " and "
                code { "ErrorTable" }
                plain " are keyword-schema presets over "
                code { "Table" }
                plain " for an object's fields and an endpoint's errors."
              end
            end

            # A Section whose description IS a live Endpoint — the real component,
            # not a mock-up.
            DocsUI::Section(
              "Create a webhook endpoint",
              description: DocsUI::Endpoint.new(:post, "/api/webhook_endpoints")
            ) do
              prose { p { "Registers a destination URL for outbound event notifications." } }
              render DocsUI::FieldTable.new(
                [
                  { name: "url", type: "string", required: true, description: "HTTPS destination URL." },
                  { name: "description", type: "string", description: "Optional internal label." },
                  { name: "events", type: "array", required: true, description: [ :md, "Event types, e.g. `payment_link.paid`." ] }
                ]
              )
              render DocsUI::ErrorTable.new(
                [
                  { scenario: "Missing or invalid API key", status: "401", type: "authentication_error" },
                  { scenario: "Non-HTTPS URL", status: "422", type: "validation_error", param: "url" },
                  { scenario: "Unknown event name", status: "422", type: "validation_error", param: "events" }
                ]
              )
            end

            prose { p { "The calls that produced the block above:" } }
            DocsUI::Code(<<~RUBY)
              DocsUI::Section("Create a webhook endpoint",
                description: DocsUI::Endpoint.new(:post, "/api/webhook_endpoints")) do
                render DocsUI::FieldTable.new([
                  { name: "url", type: "string", required: true, description: "HTTPS destination URL." },
                  { name: "events", type: "array", required: true, description: [:md, "e.g. `payment_link.paid`."] }
                ])
                render DocsUI::ErrorTable.new([
                  { scenario: "Non-HTTPS URL", status: "422", type: "validation_error", param: "url" }
                ])
              end
            RUBY

            DocsUI::Callout(:tip) do
              plain "Verb → colour is a frozen Hash of literal badge classes ("
              code { "GET" }
              plain " → success, "
              code { "POST" }
              plain " → primary, "
              code { "PATCH/PUT" }
              plain " → warning, "
              code { "DELETE" }
              plain " → error). An unknown verb renders a neutral badge — no raise."
            end

            render DocsUI::PropTable.new(
              [
                [ "DocsUI::Endpoint.new(method, path)", "Symbol/String, String", "—", "Method badge + monospace path; renders inline." ],
                [ "DocsUI::FieldTable.new(fields)", "Array<Hash>", "—", "Each: { name:, type:, required: false, description: }." ],
                [ "DocsUI::ErrorTable.new(errors)", "Array<Hash>", "—", "Each: { scenario:, status:, type:, param: nil }; Param column auto-hidden." ],
                [ "Section(description:)", "String, proc, or component", "nil", "Now also accepts a Phlex component instance." ]
              ],
              headers: [ "Call", "Type", "Default", "Description" ]
            )
          end
        end

        def request_example_section
          DocsUI::Section(
            "RequestExample & JsonResponse",
            description: "The API-docs kit — declare a request once, get every client tab; render a Ruby hash as a JSON response."
          ) do
            prose do
              p do
                code { "DocsUI::RequestExample" }
                plain " turns one structured request declaration ("
                code { "method:" }
                plain "/"
                code { "path:" }
                plain "/"
                code { "body:" }
                plain ") into a "
                code { "DocsUI::Example" }
                plain " with one tab per configured client — "
                code { "curl" }
                plain ", "
                code { "javascript" }
                plain ", "
                code { "ruby" }
                plain ", "
                code { "python" }
                plain " by default (a site adds its own, e.g. a "
                code { "cli" }
                plain " tab). "
                code { "DocsUI::JsonResponse" }
                plain " renders a Ruby Hash as pretty-printed JSON — no hand-rolled "
                code { "deep_stringify" }
                plain "."
              end
            end

            # Live: one declaration → four client tabs, plus a JSON response.
            DocsUI::Section(
              "Create a payment link",
              description: DocsUI::Endpoint.new(:post, "/v1/payment_links")
            ) do
              prose { p { "Creates a shareable payment link for a fixed amount." } }
              render DocsUI::FieldTable.new(
                [
                  { name: "amount", type: "integer", required: true, description: "Amount in the smallest currency unit." },
                  { name: "currency", type: "string", required: true, description: "ISO 4217 currency code." },
                  { name: "description", type: "string", description: "Shown to the payer at checkout." }
                ]
              )
              render DocsUI::RequestExample.new(
                method: :post,
                path: "/v1/payment_links",
                body: { amount: 4900, currency: "usd", description: "Pro plan" }
              )
              prose { p { "A successful response:" } }
              render DocsUI::JsonResponse.new(
                {
                  id: "plink_1a2b3c",
                  object: "payment_link",
                  amount: 4900,
                  currency: "usd",
                  url: "https://pay.example.com/plink_1a2b3c",
                  active: true
                }
              )
            end

            prose { p { "The calls that produced the block above:" } }
            DocsUI::Code(<<~RUBY)
              render DocsUI::RequestExample.new(
                method: :post,
                path: "/v1/payment_links",
                body: { amount: 4900, currency: "usd", description: "Pro plan" }
              )
              render DocsUI::JsonResponse.new(
                { id: "plink_1a2b3c", object: "payment_link", amount: 4900,
                  currency: "usd", url: "https://pay.example.com/plink_1a2b3c", active: true }
              )
            RUBY

            DocsUI::Callout(:tip) do
              plain "The client set, base URL, and example auth header are config: "
              code { "c.api_clients" }
              plain " (defaults + your overrides), "
              code { "c.api_base_url" }
              plain ", and "
              code { "c.api_auth_header" }
              plain ". Override a default token to swap in an SDK-flavored snippet; add a new token (e.g. "
              code { "cli" }
              plain ") to append a tab."
            end

            render DocsUI::PropTable.new(
              [
                [ "RequestExample method:/path:", "Symbol/String, String", "—", "The HTTP verb and path (path is appended to c.api_base_url)." ],
                [ "RequestExample body:", "Hash, nil", "nil", "Request payload; deep-stringified into each snippet. Omit for a GET." ],
                [ "RequestExample query:/headers:", "Hash", "{}", "Query params and extra headers merged into every snippet." ],
                [ "RequestExample clients:", "Array<Symbol>, nil", "all configured", "Filter/order the tabs (e.g. [:curl, :ruby])." ],
                [ "JsonResponse.new(body)", "Hash or String", "—", "Hash → pretty JSON with string keys; String → passed through." ],
                [ "JsonResponse filename:", "String", '"response.json"', "The code block's title-bar filename." ]
              ],
              headers: [ "Call", "Type", "Default", "Description" ]
            )
          end
        end

        def callout_section
          DocsUI::Section("Callout", description: "note / tip / warning — a daisyUI alert with a lucide icon.") do
            DocsUI::Callout(:note) { "This is a note callout." }
            DocsUI::Callout(:tip) { "A tip callout — for handy asides." }
            DocsUI::Callout(:warning) { "A warning callout — for gotchas." }
            prose { p { "The calls that produced the boxes above:" } }
            DocsUI::Code(<<~RUBY)
              DocsUI::Callout(:note)    { "This is a note callout." }
              DocsUI::Callout(:tip)     { "A tip callout." }
              DocsUI::Callout(:warning) { "A warning callout." }
            RUBY
            render DocsUI::PropTable.new(
              [
                [ "level", "Symbol", ":note", "Alert style — :note / :tip / :warning." ],
                [ "title", "String, nil", "nil", "Optional heading above the body." ],
                [ "block", "Phlex block", "—", "The callout body." ]
              ],
              headers: [ "Arg", "Type", "Default", "Description" ]
            )
          end
        end

        def icon_section
          DocsUI::Section("Icon", description: "A lucide icon by name; extra attributes pass through.") do
            div(class: "flex gap-4 not-prose") do
              DocsUI::Icon("rocket", class: "size-6")
              DocsUI::Icon("book-open", class: "size-6")
              DocsUI::Icon("paintbrush", class: "size-6")
            end
            prose { p { "The calls that produced the icons above:" } }
            DocsUI::Code(<<~RUBY)
              DocsUI::Icon("rocket", class: "size-6")
              DocsUI::Icon("book-open", class: "size-6")
              DocsUI::Icon("paintbrush", class: "size-6")
            RUBY
            DocsUI::Callout(:note) do
              plain "Icons no-op gracefully if "
              code { "rails_icons" }
              plain " isn't configured — nothing renders, no error."
            end
            render DocsUI::PropTable.new(
              [
                [ "name", "String", "—", "The lucide icon name, e.g. \"rocket\"." ],
                [ "**attributes", "Hash", "{}", "Extra HTML attributes (class:, etc.) passed to the icon." ]
              ],
              headers: [ "Arg", "Type", "Default", "Description" ]
            )
          end
        end

        def on_this_page_section
          DocsUI::Section("OnThisPage", description: "The auto-TOC — the panel Shell renders from your on_page setting.") do
            prose do
              p do
                plain "The TOC is built from the page's "
                code { "Section" }
                plain " anchors. You don't construct it — "
                code { "Shell" }
                plain " renders it based on the page's "
                code { "on_page" }
                plain " setting. Set the mode per page or as a config default."
              end
            end
            DocsUI::Code(<<~RUBY)
              class Views::Docs::Pages::Api < DocsUI::Page
                on_page :toggle   # :panel | :toggle | :sidebar | false
              end
            RUBY
            render DocsUI::PropTable.new(
              [
                [ "mode", "Symbol", ":panel", "Placement — :panel (aside) / :toggle (button) / :sidebar." ],
                [ "title", "String", '"On this page"', "The TOC heading." ]
              ],
              headers: [ "Arg", "Type", "Default", "Description" ]
            )
          end
        end

        def sidebar_section
          DocsUI::Section("Sidebar", description: "The left nav — built from your config, rendered by Shell.") do
            prose do
              p do
                plain "The sidebar is driven entirely by "
                code { "DocsKit.configuration.nav" }
                plain " — a callable returning grouped "
                code { "DocsKit::NavItem" }
                plain "s. "
                code { "Shell" }
                plain " renders it, so you configure it rather than construct it."
              end
            end
            DocsUI::Code(<<~RUBY, filename: "config/initializers/docs_kit.rb")
              DocsKit.configure do |c|
                c.nav = -> { { "Docs" => Doc.grouped } }
              end
            RUBY
            render DocsUI::PropTable.new(
              [
                [ "(none)", "—", "—", "No args — reads DocsKit.configuration.nav." ]
              ],
              headers: [ "Arg", "Type", "Default", "Description" ]
            )
          end
        end

        def theme_switcher_section
          DocsUI::Section("ThemeSwitcher", description: "The theme dropdown — built from your config, rendered by Shell.") do
            prose do
              p do
                plain "The dropdown in the topbar is a "
                code { "DocsUI::ThemeSwitcher" }
                plain ". It lists "
                code { "DocsKit.configuration.themes" }
                plain " — which must match the daisyUI "
                code { "@plugin" }
                plain " block in your Tailwind entry. "
                code { "Shell" }
                plain " renders it for you."
              end
            end
            DocsUI::Code(<<~RUBY, filename: "config/initializers/docs_kit.rb")
              DocsKit.configure do |c|
                c.themes = %w[dark light synthwave dracula night]
              end
            RUBY
            render DocsUI::PropTable.new(
              [
                [ "(none)", "—", "—", "No args — reads DocsKit.configuration.themes." ]
              ],
              headers: [ "Arg", "Type", "Default", "Description" ]
            )
          end
        end
      end
    end
  end
end
