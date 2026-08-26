# frozen_string_literal: true

module Views
  module Docs
    module Pages
      # The introduction page: what docs-kit is, the mental model behind it, and
      # a scannable tour of the whole surface — each feature linking to its page.
      class Overview < DocsUI::Page
        title "Overview"
        eyebrow "Getting started"

        def lead = "The shared Phlex chrome for a Rails docs site — you write page bodies, docs-kit renders the rest."

        def content
          what_is_section
          mental_model_section
          what_you_get_section
          next_steps_section
        end

        private

        def what_is_section
          DocsUI::Section("What is docs-kit", description: "A gem, not a template.") do
            md <<~'MD'
              **docs-kit** is a Ruby gem that gives you the shared chrome for a
              Rails documentation site: the topbar, the responsive sidebar, the
              theme switcher, the content column, an automatic "On this page" TOC,
              and syntax-highlighted code blocks.

              It's built on [`phlex-rails`](https://www.phlex.fun) and
              [`daisyUI`](https://daisyui.com). You write page bodies as Phlex
              components — docs-kit renders everything around them.
            MD
          end
        end

        def mental_model_section
          DocsUI::Section("The mental model", description: "Configure the chrome; don't re-author it.") do
            md <<~'MD'
              The chrome — `Shell`, `Sidebar`, `Page` — is byte-identical across
              every site that uses docs-kit. The only thing that differs is
              `DocsKit.configure`. Two sites look and behave consistently for free,
              because they share the same components. You change the brand, the
              themes, and the nav — never the layout code.
            MD

            DocsUI::Code(<<~RUBY, filename: "config/initializers/docs_kit.rb")
              DocsKit.configure do |c|
                c.brand          = "My Project"          # only this differs per site
                c.themes         = %w[dark light]        # the chrome itself is identical
                c.nav_registries = { "Docs" => Doc }     # sidebar derives from the registry
              end
            RUBY

            DocsUI::Callout(:tip) do
              "This very site is built with docs-kit — the topbar, sidebar, and TOC " \
                "you're looking at are the exact chrome your site will get."
            end
          end
        end

        def what_you_get_section
          DocsUI::Section("What you get", description: "The whole surface, in the box — each row links to its page.") do
            md <<~'MD'
              #### The chrome

              - **Shared shell + responsive sidebar + theme switcher** — the same
                topbar, nav, and layout on every screen size, remembered in
                `localStorage`. See [Components](/docs/components).
              - **A theme switcher** whose list is your `c.themes` — it must match
                the daisyUI `@plugin` block in your Tailwind entry. See
                [Styling & CSS](/docs/styling).
              - **Syntax highlighting for ~200 languages** via Rouge, with a
                light + dark theme pair emitted as inline CSS — no allowlist, no
                flash. See [Code languages](/docs/languages).

              #### Authoring

              - **Markdown islands** — drop `md <<~'MD' … MD` anywhere in a page
                and get GFM (tables, lists, inline code, links) styled with the
                reading rhythm. See [Markdown authoring](/docs/markdown).
              - **The component kit** — `Section`, `Code`, `Example`, `Callout`,
                `Table`/`PropTable`, plus the **API-docs kit**
                (`Endpoint`, `RequestExample`, `JsonResponse`) that turns one
                request declaration into every client tab. See
                [Components](/docs/components) and the [API reference](/docs/api).
              - **A one-command page generator** — `rails g docs_kit:page "Title"`
                writes the Phlex class AND its one-line Registry v2 entry, both
                derived from the title. See [Authoring pages](/docs/authoring).

              #### For machines

              - **An automatic `.md` twin** — every page answers at `/docs/x.md`
                with its Markdown source, and the masthead "Markdown" action
                becomes copy-to-clipboard.
              - **`/llms.txt` + `/llms-full.txt`** — an [llmstxt.org](https://llmstxt.org)
                index and a full concatenation, served from the registry with zero
                authoring.
              - **Server-rendered search + a ⌘K palette** — a working
                `GET /docs/search` form the `docs-nav` controller enhances into a
                fuzzy palette. See [Search](/docs/search).
              - **An optional read-only MCP server** — `POST /mcp` exposing
                `list_pages` / `get_page` / `search_docs` over the registry when
                the `mcp` gem is present. See [AI & agents](/docs/ai).
              - **AGENTS.md scaffolding** — the install generator writes an
                `AGENTS.md` authoring contract plus a Claude Code
                `write-docs-page` skill, so agents author pages the right way.

              #### Toolchain

              - **Shipped RuboCop cops** — `DocsKit/RenderComponentPreferred`
                (steer to the kit helper form) and
                `DocsKit/EscapedInterpolationInHeredoc` (kill the `\#{…}` escape
                tax in Markdown heredocs). See [Configuration](/docs/configuration).
              - **An idempotent install** — `docs_kit:install` is safe to re-run,
                and `--sync` runs only the additive wiring to upgrade an existing
                site without touching your pages. See [Installation](/docs/installation).
              - **`docs-kit new` + a single reusable deploy workflow** — scaffold a
                whole site, then ship it with dash + GHCR. See [Deploy](/docs/deploy).
            MD
          end
        end

        def next_steps_section
          DocsUI::Section("Next steps") do
            md <<~'MD'
              Start with [Installation](/docs/installation) to add the gem and
              render your first page. Then read [Configuration](/docs/configuration)
              to set your brand, themes, and nav, and [Authoring pages](/docs/authoring)
              to learn the DocsUI kit — the building blocks for every page body.
            MD
          end
        end
      end
    end
  end
end
