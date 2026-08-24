# frozen_string_literal: true

module DocsKit
  class MarkdownExport
    # The Nokogiri → GFM visitor. Splits into two passes over the bounded kit
    # vocabulary: block-level elements (this class) produce Markdown lines
    # separated by blank lines; inline elements (Inline) produce a single run of
    # text. Unknown block elements recurse into their children (text survives, the
    # wrapper is dropped), matching the issue's "recurse into children" rule.
    class Blocks
      HEADINGS = { "h1" => "#", "h2" => "##", "h3" => "###", "h4" => "####" }.freeze
      LIST_TAGS = %w[ul ol].freeze

      def initialize(export)
        @export = export
        @inline = Inline.new(export)
      end

      # Render a container's block children, joined by blank lines. Blocks that
      # yield nothing (whitespace-only text nodes) are dropped so no stray blank
      # lines accumulate.
      def render(node)
        node.children
            .filter_map { |child| block(child) }
            .reject(&:empty?)
            .join("\n\n")
      end

      private

      # Dispatch one node to its block rendering. A bare text node contributes its
      # text only when non-blank (structural whitespace between block tags is
      # dropped). An unknown element recurses.
      def block(node)
        return node.text.strip.empty? ? nil : @inline.render_node(node) if node.text?
        return nil unless node.element?

        name = node.name
        return heading(node, HEADINGS[name]) if HEADINGS.key?(name)

        dispatch(node, name)
      end

      def dispatch(node, name)
        # A DocsUI::Callout (div[data-md-callout]) becomes a labelled blockquote —
        # checked BEFORE the structural-div recurse so it isn't flattened away.
        level = node["data-md-callout"]
        return callout(node, level) if level

        block_element(node, name)
      end

      def block_element(node, name)
        case name
        when "p" then paragraph(node)
        when "pre" then code_fence(node)
        when "ul", "ol" then list(node, ordered: name == "ol")
        when "table" then Table.new(@export).render(node)
        when "blockquote" then blockquote(node)
        else leaf(node, name) # hr/img, else recurse into an unknown wrapper
        end
      end

      # The self-contained leaf blocks; anything else is a structural wrapper
      # (section/header/div/…) whose children carry the content, so recurse.
      def leaf(node, name)
        case name
        when "hr" then "---"
        when "img" then @inline.image(node)
        else render(node)
        end
      end

      # A heading's text. DocsUI::Section wraps its title in a self-referencing
      # anchor (a deep-link affordance) with a decorative "#" span; both are
      # chrome, so render the heading's inner TEXT rather than a `[Title](#id)`
      # link. The Inline pass already drops the "#" span.
      def heading(node, hashes)
        "#{hashes} #{@inline.heading_text(node)}"
      end

      def paragraph(node)
        @inline.render(node)
      end

      # A DocsUI::Code block is pre inside div[data-md-lang]; the fence carries
      # that resolved language (blank for plaintext → a language-less fence). The
      # source is the <pre>'s text, un-escaped (Nokogiri already decoded entities).
      def code_fence(node)
        lang = fence_language(node)
        source = node.text.delete_suffix("\n")
        "```#{lang}\n#{source}\n```"
      end

      # The language is on the DocsUI::Code wrapper (div[data-md-lang]) around the
      # <pre>. "plaintext" (or absent) means no language token on the fence.
      def fence_language(node)
        lang = node.ancestors("[data-md-lang]").first&.[]("data-md-lang").to_s
        lang == "plaintext" ? "" : lang
      end

      # A blockquote's block children, each line prefixed "> ".
      def blockquote(node)
        quote(render(node))
      end

      # A callout → `> **Label:** body` as a blockquote. Callout stamps a
      # `div.font-semibold` title (present only when title: is given) and a
      # `div.text-sm` body. Read them separately: the author's title is the label
      # when present (else the level label), and only the body div is rendered so
      # the title never fuses into the body text.
      def callout(node, level)
        title = node.at_css(".font-semibold")
        body_node = node.at_css(".text-sm") || node
        label = title ? @inline.render(title).strip : CALLOUT_LABELS.fetch(level, "Note")
        body = @inline.render(body_node).strip
        quote("**#{label}:** #{body}")
      end

      def quote(text)
        text.split("\n").map { |line| line.empty? ? ">" : "> #{line}" }.join("\n")
      end

      # A list, rendered at the given indent depth. Each item is a marker (- or
      # 1./2./…) plus its inline text; nested lists indent two spaces per level.
      def list(node, ordered:, depth: 0)
        index = 0
        items(node).map do |li|
          index += 1
          marker = ordered ? "#{index}. " : "- "
          "#{'  ' * depth}#{marker}#{item(li, depth)}"
        end.join("\n")
      end

      def items(node)
        node.children.select { |child| child.element? && child.name == "li" }
      end

      # An <li>'s content: its inline text, plus any nested list indented one level
      # deeper on following lines.
      def item(node, depth)
        text = @inline.render(inline_children(node)).strip
        nested = node.children.filter_map do |child|
          next unless list?(child)

          "\n#{list(child, ordered: child.name == 'ol', depth: depth + 1)}"
        end
        "#{text}#{nested.join}"
      end

      # The li's children minus nested lists (those render on their own lines).
      def inline_children(node)
        node.children.reject { |child| list?(child) }
      end

      def list?(node)
        node.element? && LIST_TAGS.include?(node.name)
      end
    end
  end
end
