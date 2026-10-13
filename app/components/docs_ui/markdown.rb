# frozen_string_literal: true

require "commonmarker"

module DocsUI
  # A Markdown "island" for prose authoring inside a Phlex page. Parses GFM with
  # commonmarker (v2, comrak) and walks the AST emitting Phlex nodes — it never
  # `raw`s commonmarker's HTML. That buys three things:
  #
  #   * Phlex-native escaping — author text is escaped by Phlex, so no html_safe
  #     on free text (Critical Rule 7) and #{} in prose renders literally.
  #   * Fenced code delegated to DocsUI::Code (Rouge, configured aliases,
  #     plaintext fallback) — highlighted identically to a hand-written Code block.
  #   * The exact DocsUI::Prose typography classes on the wrapper, so Markdown
  #     prose is visually identical to hand-authored Prose.
  #
  #   render DocsUI::Markdown.new(<<~MD)
  #     Write **prose** as GFM. Fenced blocks are highlighted:
  #
  #     ```ruby
  #     puts "hi"
  #     ```
  #   MD
  #
  # Raw HTML in the source is dropped (the AST's html_block/html_inline nodes are
  # skipped) — there is no config to enable it. Headings render as styled h3/h4;
  # document structure and the TOC stay with DocsUI::Section.
  class Markdown < Phlex::HTML
    # Reuse Prose's child-selector typography vocabulary verbatim so Markdown and
    # hand-authored Prose read identically.
    CLASSES = Prose::CLASSES

    # The kit table wrapper + daisyUI table classes (matches DocsUI's table look).
    TABLE_WRAPPER = "not-prose my-4 overflow-x-auto rounded-box border border-base-300"
    TABLE_CLASSES = "table table-sm table-zebra"

    # ![alt](src) → <img>, asset-pipeline resolved (see MarkdownImages).
    include MarkdownImages

    # Render source as INLINE markdown: no Prose wrapper div, and a single
    # top-level paragraph is unwrapped so its inline children (strong/em/code/
    # link) sit directly in the surrounding element. Used for a [:md, "…"] table
    # cell — the cell's <td> is the container, so a block <p>/typography div would
    # be wrong there.
    def self.inline(source) = new(source, inline: true)

    def initialize(source, inline: false)
      # commonmarker v2 raises unless the text is UTF-8. Author heredocs already
      # are, but nil.to_s / a US-ASCII string would crash the render — normalize
      # at the boundary so any input parses.
      @source = source.to_s.encode(Encoding::UTF_8)
      @inline = inline
    end

    def view_template
      return visit_inline(document) if @inline

      div(class: CLASSES) { visit(document) }
    end

    private

    def document
      Commonmarker.parse(@source)
    end

    # Inline render: unwrap each top-level paragraph to its inline children (no
    # <p>), so `[:md, "a **note**"]` becomes `a <strong>note</strong>` inside the
    # cell rather than a block paragraph. Non-paragraph blocks (a stray list) still
    # render as themselves. Adjacent blocks get a joining space so unwrapping never
    # fuses text ("one" + "two" → "one two", not "onetwo").
    def visit_inline(node)
      node.each_with_index do |child, i|
        whitespace unless i.zero?
        child.type == :paragraph ? visit_children(child) : visit(child)
      end
    end

    # Emit each child of a node in order.
    def visit_children(node)
      node.each { |child| visit(child) }
    end

    # Dispatch a node to its handler (node_<type>). A node type with no handler
    # just recurses into its children; html_block/html_inline have handlers that
    # drop them (see below).
    def visit(node)
      handler = "node_#{node.type}"
      respond_to?(handler, true) ? send(handler, node) : visit_children(node)
    end

    def node_document(node) = visit_children(node)

    def node_paragraph(node) = p { visit_children(node) }

    # Demote so Markdown headings never collide with the page masthead/section
    # headings: h1→h3, h2→h4, anything deeper caps at h4.
    def node_heading(node)
      case node.header_level
      when 1 then h3 { visit_children(node) }
      else h4 { visit_children(node) }
      end
    end

    def node_text(node) = plain(node.string_content)

    def node_strong(node)
      strong { visit_children(node) }
    end

    def node_emph(node)
      em { visit_children(node) }
    end

    def node_strikethrough(node)
      del { visit_children(node) }
    end

    def node_code(node)
      code { node.string_content }
    end

    # Fenced code goes through DocsUI::Code so it is highlighted (Rouge) exactly
    # like a hand-written block. No fence language falls back to plaintext.
    def node_code_block(node)
      lexer = node.fence_info.to_s.strip
      lexer = "plaintext" if lexer.empty?
      render DocsUI::Code.new(node.string_content, lexer:)
    end

    def node_link(node)
      a(href: node.url) { visit_children(node) }
    end

    def node_list(node)
      node.list_type == :ordered ? ol { visit_children(node) } : ul { visit_children(node) }
    end

    # In a tight list, GFM renders items WITHOUT a <p> wrapper (and Prose styles
    # `li` directly). Unwrap the item's paragraph children when the parent list is
    # tight; a loose list keeps the paragraphs (spacing between items).
    def node_item(node)
      tight = node.parent&.list_tight
      li do
        node.each do |child|
          tight && child.type == :paragraph ? visit_children(child) : visit(child)
        end
      end
    end

    def node_block_quote(node)
      blockquote { visit_children(node) }
    end

    def node_thematic_break(_node) = hr

    def node_softbreak(_node) = whitespace

    def node_linebreak(_node) = br

    # A GFM table: the first row is the header (th), the rest are body cells (td).
    def node_table(node)
      rows = node.to_a
      div(class: TABLE_WRAPPER) do
        table(class: TABLE_CLASSES) do
          thead { table_row(rows.first, header: true) } if rows.any?
          tbody { rows.drop(1).each { |row| table_row(row) } } if rows.length > 1
        end
      end
    end

    def table_row(row, header: false)
      tr do
        row.each do |cell|
          if header
            th { visit_children(cell) }
          else
            td { visit_children(cell) }
          end
        end
      end
    end

    # Raw HTML is dropped — no live tags from author Markdown.
    def node_html_block(_node) = nil
    def node_html_inline(_node) = nil
  end
end
