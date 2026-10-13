# frozen_string_literal: true

module Views
  module Docs
    module Pages
      # The `md` island: the everyday prose path. Write GFM as a single-quoted
      # heredoc; it renders as Prose-identical typography, delegates fences to
      # Rouge, and flows into the page's .md twin.
      class Markdown < DocsUI::Page
        title "Markdown authoring"
        eyebrow "Authoring"

        def lead = "Write prose as Markdown with the md helper — GFM in, Prose-identical typography out, and every fence highlighted by Rouge."

        def content
          md_helper_section
          heredoc_section
          gfm_section
          inline_section
          escaping_section
          twin_section
          args_section
        end

        private

        def md_helper_section
          DocsUI::Section("The md helper",
                          description: "The everyday authoring entry point — a block of GFM, styled like Prose.") do
            md <<~'MD'
              `md` is the prose path you reach for on almost every page. Hand it a
              heredoc of GFM Markdown and it renders a `DocsUI::Markdown` island —
              a block styled with the **exact** typography of a hand-authored
              [Prose](/docs/components) block, so `md` prose and `prose do … end`
              read identically.
            MD

            DocsUI::Code(<<~'RUBY')
              md <<~'MD'
                Write **prose** as Markdown — `inline code`, [links](/docs/overview),
                lists, and tables all styled like Prose.
              MD
            RUBY

            md <<~'MD'
              This whole page is written with `md`. Under the hood the helper is
              `render DocsUI::Markdown.new(source)` — a lowercase method so the
              heredoc lands without the parens-with-blocks Ruby trap. It lives on
              `DocsUI::Page` (via the `PageHelpers` mixin) alongside `prose` and
              `example`; it is not a global, so a bare Phlex component would need
              to include `DocsUI::PageHelpers` to get it.
            MD

            DocsUI::Callout(:tip) do
              plain "Markdown is prose-only. Document structure — the section headings that feed the "
              a(href: "/docs/on-this-page") { "On this page" }
              plain " TOC — stays with "
              code { "DocsUI::Section" }
              plain ", not with an island heading."
            end
          end
        end

        def heredoc_section
          DocsUI::Section("Always single-quote the heredoc",
                          description: "A single-quoted heredoc passes interpolation and backslashes through as literal author text.") do
            md <<~'MD'
              Use a **single-quoted** heredoc — `<<~'MD'` — for every `md` block.
              With single quotes Ruby does no interpolation, so `#{...}` and
              backslashes reach the parser as the literal characters you typed.
              That matters constantly in docs prose, where you *write about*
              interpolation and escapes rather than perform them.
            MD

            DocsUI::Code(<<~'RUBY')
              # Good — single-quoted: the reader sees the literal text.
              md <<~'MD'
                Write `#{user.name}` to interpolate, and `\d+` for a digit.
              MD

              # Trap — double-quoted: Ruby evaluates #{user.name} before Phlex
              # ever sees it, and eats the backslash in \d.
              md <<~MD
                Write `#{user.name}` ...
              MD
            RUBY

            md <<~'MD'
              Even a double-quoted heredoc is still *safe* — Phlex escapes all
              author free text, so nothing injects markup (see
              [Escaping](#escaping-raw-html) below). But it will silently *change
              your words*: `#{user.name}` becomes whatever that expression
              evaluates to, and `\d` loses its backslash. Single-quoting is the
              intended convention precisely so the prose you wrote is the prose the
              reader gets.
            MD
          end
        end

        def gfm_section
          DocsUI::Section("The GFM you can write",
                          description: "Headings, lists, tables, fenced code, images, links, blockquotes — parsed by commonmarker.") do
            md <<~'MD'
              Islands parse **GitHub-Flavored Markdown** with commonmarker (v2 /
              comrak). The full everyday vocabulary is here:

              ## Headings, emphasis, lists

              A `#` heading renders as an `<h3>`; `##` and anything deeper collapse
              to `<h4>` — demoted so an island heading never collides with the page
              masthead or a `DocsUI::Section` heading. Hierarchy inside an island is
              intentionally flat.

              Inline you get **strong**, *emphasis*, ~~strikethrough~~, and
              `inline code`. Lists come tight or loose, bullet or ordered, nested:

              - a bullet item,
              - another, with a nested list:
                1. first ordered step,
                2. second ordered step.

              ## Tables

              A GFM pipe table renders as the kit's daisyUI table — a `not-prose`
              overflow wrapper around a `table table-sm table-zebra`. The first row
              is the header, the rest the body:

              | Syntax        | Renders as        |
              | ------------- | ----------------- |
              | `**bold**`    | strong            |
              | `~~gone~~`    | strikethrough     |
              | `` `code` ``  | inline code       |

              ## Fenced code → Rouge

              A fenced ` ```lang ` block routes through
              [`DocsUI::Code`](/docs/components), so it is Rouge-highlighted exactly
              like a hand-written Code block — same wrapper, same token spans, same
              configured [language aliases](/docs/languages):

              ```ruby
              class Doc
                extend DocsKit::Registry
                page "Overview", group: "Getting started"
              end
              ```

              No fence language — or an unknown one — falls back to plaintext and
              never raises.

              ## Images

              `![alt](path "title")` renders a lazy-loaded `<img>`. A relative
              path resolves through your site's asset pipeline — `og/og.png`
              becomes the digested `/assets/og/og-….png` — while an absolute,
              protocol-relative or root-relative URL is used as written. The alt
              is the description's plain text, and a `javascript:` or `data:`
              source renders nothing:

              ![The docs-kit landing page](og/og.png "This site's social-share card")

              ## Links, blockquotes, rules

              [Links](/docs/authoring) are ordinary `[text](url)`. A `>` line is a
              blockquote:

              > Prose written as Markdown, styled with the reading rhythm.

              And a line of three dashes is a thematic break — the horizontal rule
              just below this paragraph:

              ---

              Everything above the rule was one `md` island.
            MD

            DocsUI::Callout(:note) do
              plain "A soft line break (a single newline inside a paragraph) becomes a single space, not a "
              code { "<br>" }
              plain ". Only a hard break — two trailing spaces or a trailing backslash — becomes a "
              code { "<br>" }
              plain "."
            end
          end
        end

        def inline_section
          DocsUI::Section("Inline markdown in a table cell",
                          description: "Markdown.inline renders inline children with no Prose wrapper — for a [:md, …] cell.") do
            md <<~'MD'
              `DocsUI::Markdown.inline(source)` is the inline sibling: **no** Prose
              wrapper div, and a single top-level paragraph is unwrapped so its
              inline children — strong, em, code, a link — sit directly in the
              surrounding element. It exists for the `[:md, "…"]` cell form of
              [`DocsUI::Table` / `PropTable` / `FieldTable`](/docs/components),
              where the `<td>` is already the container and a block paragraph would
              be wrong.
            MD

            DocsUI::Table(
              [ "name", "description" ],
              [
                [ [ :code, "events" ], [ :md, "Event types, e.g. `payment_link.paid`." ] ],
                [ [ :code, "amount" ], [ :md, "Amount in the **smallest** currency unit." ] ]
              ]
            )

            prose { p { "The description cells above are inline markdown — the call that produced the table:" } }

            DocsUI::Code(<<~'RUBY')
              DocsUI::Table(
                [ "name", "description" ],
                [
                  [ [ :code, "events" ], [ :md, "Event types, e.g. `payment_link.paid`." ] ],
                  [ [ :code, "amount" ], [ :md, "Amount in the **smallest** currency unit." ] ]
                ]
              )
            RUBY

            md <<~'MD'
              Adjacent top-level blocks get a joining space when unwrapped, so two
              paragraphs never fuse (`"one"` + `"two"` → `"one two"`, not
              `"onetwo"`). You rarely call `.inline` directly — the `[:md, …]` cell
              form invokes it for you.
            MD
          end
        end

        def escaping_section
          DocsUI::Section("Escaping & raw HTML",
                          id: "escaping-raw-html",
                          description: "Author free text is Phlex-escaped; raw HTML tags are dropped entirely.") do
            md <<~'MD'
              Because the island *walks the commonmarker AST and emits native Phlex
              nodes* — it never `raw`s commonmarker's HTML string — all author free
              text is Phlex-escaped. There is no `html_safe` on prose (Critical Rule
              7 holds), and `<`, `>`, `&` inside inline `` `code` `` are safe.

              Raw HTML is dropped: `html_block` and `html_inline` AST nodes are
              skipped entirely, so author Markdown can never inject a live
              `<script>` or `<div onclick>` tag. There is no config to re-enable it.
            MD

            DocsUI::Callout(:warning) do
              plain "Only the tags are dropped, not the text between them. The body of "
              code { "<script>alert(1)</script>" }
              plain " survives as a separate commonmarker text node — inert, Phlex-escaped prose that reads as the literal words "
              code { "alert(1)" }
              plain ". Never executable, but not erased either."
            end

            md <<~'MD'
              Input is also normalized at the boundary: the initializer does
              `source.to_s.encode(Encoding::UTF_8)`, so a `nil` source renders an
              empty wrapper (never raises) and a US-ASCII heredoc parses fine.
            MD
          end
        end

        def twin_section
          DocsUI::Section("Markdown flows into the .md twin",
                          description: "Every page has a raw-Markdown twin; the masthead links it.") do
            md <<~'MD'
              Every docs page has a `.md` twin — the same page served as raw
              Markdown at its path plus `.md`. The **Markdown** button in this
              page's masthead points at it. With JavaScript off, the link simply
              opens the raw Markdown (a working no-JS fallback); with JS on, the one
              [`docs-nav`](/docs/ai) controller intercepts the click, fetches the
              `.md`, copies it to your clipboard, and prevents the navigation.
            MD

            DocsUI::Code(<<~'RUBY')
              # DocsUI::Page renders this automatically when
              # DocsKit.configuration.page_markdown_action is true (the default).
              render DocsUI::MarkdownAction.new(request.path)
            RUBY

            md <<~'MD'
              The affordance is a new target + action on the single `docs-nav`
              controller — the one-controller rule holds. The `.md` twin *content*
              itself is produced by `DocsKit::Controller#render_page` →
              `DocsKit::MarkdownExport`, not by this button. Disable the button
              site-wide with `c.page_markdown_action = false`.
            MD

            DocsUI::Callout(:note) do
              plain "The twin href is idempotent and query-preserving: "
              code { "/docs/markdown" }
              plain " → "
              code { "/docs/markdown.md" }
              plain ", "
              code { "/x?a=1" }
              plain " → "
              code { "/x.md?a=1" }
              plain ", and a path already ending in "
              code { ".md" }
              plain " is left untouched."
            end
          end
        end

        def args_section
          DocsUI::Section("DocsUI::Markdown args",
                          description: "The component behind the md helper.") do
            render DocsUI::PropTable.new(
              [
                [ "source", "String, nil", "—", "The GFM to render. nil/non-UTF-8 is normalized (never raises)." ],
                [ "inline:", "Boolean", "false", "No Prose wrapper; unwrap a lone top-level paragraph (for a [:md, …] cell)." ],
                [ "md(source)", "page helper", "—", "render DocsUI::Markdown.new(source) — the everyday path." ],
                [ ".inline(source)", "class method", "—", "== new(source, inline: true); used by [:md, …] table cells." ]
              ],
              headers: [ "Arg", "Type", "Default", "Description" ]
            )
          end
        end
      end
    end
  end
end
