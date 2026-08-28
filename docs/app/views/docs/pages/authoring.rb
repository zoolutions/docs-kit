# frozen_string_literal: true

module Views
  module Docs
    module Pages
      # How to write a documentation page: a Phlex class, a registry entry, the
      # DocsUI building blocks (with pointers to their dedicated pages), and the
      # automatic "On this page" TOC.
      class Authoring < DocsUI::Page
        title "Authoring pages"
        eyebrow "Authoring"

        def lead = "One command scaffolds a page — the class and its registry line. Then write content; the shell, masthead, and TOC come free."

        def content
          one_command_section
          page_is_a_class_section
          register_section
          building_blocks_section
          toc_section
        end

        private

        def one_command_section
          DocsUI::Section("One command",
                          description: "rails g docs_kit:page writes the class AND registers it — both derived from the title.") do
            DocsUI::Code(<<~SHELL, lexer: :shell)
              rails g docs_kit:page "Getting Started" --group=Guide
            SHELL

            md <<~'MD'
              That writes `app/views/docs/pages/getting_started.rb` (slug
              `getting-started`, class `GettingStarted`) and injects
              `page "Getting Started", group: "Guide"` into the `Doc` registry, so
              the page is routed and in the sidebar the moment you fill in
              `#content`. Every derivation is overridable:

              - `--slug=auth` — the URL slug,
              - `--view=OauthGuide` — the class basename,
              - `--eyebrow="Advanced"` — the eyebrow (defaults to the group),
              - `--registry=Guide` — a differently-named registry class.

              Re-running is idempotent, and a legacy hash-`entries` registry is
              left untouched (the generator prints the entry to add by hand).
            MD

            DocsUI::Callout(:tip) do
              "The rest of this page is what the generator produces — the shape to reach for when you hand-write or edit a page."
            end
          end
        end

        def page_is_a_class_section
          DocsUI::Section("A page is a Phlex class",
                          description: "Subclass DocsUI::Page, declare its metadata, fill in #content.") do
            DocsUI::Code(<<~RUBY, filename: "app/views/docs/pages/guide.rb")
              # frozen_string_literal: true

              # Compact class reference — Zeitwerk resolves it through the
              # directory-implied namespaces, so no nested-module ceremony.
              class Views::Docs::Pages::Guide < DocsUI::Page
                title "Guide"
                eyebrow "Getting started"

                def lead = "One sentence that sits under the page title."

                def content
                  DocsUI::Section("First steps", description: "What this section covers.") do
                    md <<~'MD'
                      Prose written as Markdown, styled with the reading rhythm.
                    MD

                    DocsUI::Code(<<~SOURCE, filename: "config/routes.rb")
                      Rails.application.routes.draw do
                        mount DocsKit::Engine, at: "/docs"
                      end
                    SOURCE
                  end
                end
              end
            RUBY

            md <<~'MD'
              `title` names the page, `eyebrow` groups it above the title, and
              `lead` is the summary sentence under it. Everything you render lives
              in `content`.

              The shell (topbar, sidebar, theme switcher), the page masthead, and
              the **On this page** TOC are added automatically — you only write the
              body.
            MD
          end
        end

        def register_section
          DocsUI::Section("Register the page",
                          description: "One line in the Doc registry — slug and view derive from the title.") do
            md <<~'MD'
              A page shows up once it has a `page` line in the `Doc` registry.
              `slug` and `view` derive from the title (both overridable per line),
              and `group:` sets its sidebar heading. The generator injects this
              line for you.
            MD

            DocsUI::Code(<<~RUBY, filename: "app/models/doc.rb")
              class Doc
                extend DocsKit::Registry
                path_prefix    "/docs"
                view_namespace "Views::Docs::Pages"

                page "Overview", group: "Getting started"
                page "Guide",    group: "Getting started"
                # overrides win: page "OAuth", group: "Guide", slug: "auth", view: "OauthGuide"
              end
            RUBY

            md <<~'MD'
              The sidebar derives from the registry — set
              `c.nav_registries = { "Docs" => Doc }` in the initializer and never
              hand-write a nav lambda again.
            MD

            DocsUI::Callout(:note) do
              "The sidebar only links a page whose class exists, so a page line without its class yet is a no-op — no dead links."
            end
          end
        end

        def building_blocks_section
          DocsUI::Section("The building blocks",
                          description: "The DocsUI kit you compose inside #content — and where each one is documented in full.") do
            md <<~'MD'
              Inside `#content` you reach for a small kit. The everyday four —
              a `DocsUI::Section` wrapper, `md` for Markdown prose, `DocsUI::Code`
              for a highlighted block, and `DocsUI::Callout` for an aside —
              carry most pages. The rest are specialised; each has its own
              reference page rather than being re-explained here.
            MD

            render DocsUI::Table.new(
              [ "Block", "Use for", "Full reference" ],
              [
                [ [ :code, "DocsUI::Section(title)" ], "an anchored subsection with a heading (+ optional description:)", [ :md, "[Components](/docs/components)" ] ],
                [ [ :code, "md(source)" ], "a block of GFM Markdown — the everyday prose helper", [ :md, "[Markdown authoring](/docs/markdown)" ] ],
                [ [ :code, "prose { … }" ], "hand-authored prose (p/ul/code) in a reading-rhythm wrapper", [ :md, "[Components](/docs/components)" ] ],
                [ [ :code, "DocsUI::Code(source)" ], "a Rouge-highlighted code block", [ :md, "[Code languages](/docs/languages)" ] ],
                [ [ :code, "example { |ex| … }" ], "multi-language tabbed code", [ :md, "[Code languages](/docs/languages)" ] ],
                [ [ :code, "DocsUI::Callout(level)" ], "note / tip / warning boxes", [ :md, "[Components](/docs/components)" ] ],
                [ [ :code, "DocsUI::Table / PropTable" ], "reference tables — headers + rows, or the args preset", [ :md, "[Components](/docs/components)" ] ],
                [ [ :code, "DocsUI::Endpoint / RequestExample" ], "the API-reference kit — a method+path line, client tabs, a fields table", [ :md, "[API reference](/docs/api)" ] ]
              ]
            )

            md <<~'MD'
              The primary argument is always positional —
              `Section("Title")`, `Code(source, filename:)` (the filename picks the language), `Header("Title")` — with
              modifiers as keywords (`description:`, `eyebrow:`).

              For the wrappers that take no argument, use the lowercase page
              helpers `prose` / `example` (and `md` for Markdown). A lowercase
              method takes a block without parens, so `prose do … end` just works.
              The kit forms `DocsUI::Prose()` / `DocsUI::Example()` stay valid —
              they only need the empty `()` because a bare `DocsUI::Prose do`
              parses as a constant reference (a SyntaxError).
            MD

            markdown_island_callout
          end
        end

        def markdown_island_callout
          DocsUI::Callout(:tip) do
            plain "Prose is a "
            strong { "Markdown island" }
            plain ": "
            code { "md <<~'MD'" }
            plain " parses GFM with commonmarker and emits native Phlex nodes — tables, fenced code (routed through "
            code { "DocsUI::Code" }
            plain "), links, all Phlex-escaped. Use a single-quoted heredoc so "
            code { "\#{...}" }
            plain " stays literal author text. See "
            a(href: "/docs/markdown") { "Markdown authoring" }
            plain " for the full vocabulary."
          end
        end

        def toc_section
          DocsUI::Section("The \"On this page\" TOC",
                          description: "Built for you from your section headings.") do
            prose do
              p do
                plain "Every "
                code { "DocsUI::Section" }
                plain " heading becomes an entry in the automatic "
                strong { "On this page" }
                plain " table of contents — you never list them by hand."
              end
              p do
                plain "Override its placement per page with "
                code { "on_page" }
                plain "."
              end
            end

            DocsUI::Code(<<~RUBY)
              class Views::Docs::Pages::Guide < DocsUI::Page
                on_page :toggle   # :toggle | :panel | :sidebar | false
              end
            RUBY

            prose do
              p do
                plain "See the "
                a(href: "/docs/on-this-page") { "On this page" }
                plain " reference for every mode and the site-wide default."
              end
            end
          end
        end
      end
    end
  end
end
