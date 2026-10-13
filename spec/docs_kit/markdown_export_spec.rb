# frozen_string_literal: true

# DocsKit::MarkdownExport renders a Phlex page to HTML, extracts the
# #docs-content region, and converts it to GFM with a Nokogiri visitor over the
# kit's bounded tag vocabulary. These specs assert on the SEMANTICS of the
# emitted Markdown (a heading level, a fenced block's language, a table row) —
# not brittle whole-string snapshots.
#
# The fixture is a bare Phlex host that wraps kit components in the same
# #docs-content anchor DocsUI::Shell stamps, so the converter sees exactly the
# subtree it would in production — without booting Rails to render a real Shell.
RSpec.describe DocsKit::MarkdownExport do
  # Convert a Phlex component (rendered via #call, no Rails view context) to md.
  def to_md(component, **opts)
    described_class.new(component, **opts).to_md
  end

  # A #docs-content wrapper around an authored body — the extraction anchor the
  # converter keys on. Built as a bare Phlex host so the full kit renders with
  # `.call` (as the component specs do), no Rails boot.
  def docs_content(&body)
    Class.new(Phlex::HTML) do
      include DocsUI

      define_method(:view_template) do
        div(id: "docs-content") { instance_exec(&body) }
      end
    end.new
  end

  # Convert a raw HTML fragment (wrapped in #docs-content) — the converter works
  # on rendered HTML, so a literal fragment is the most direct fixture for the
  # tag→Markdown mapping, and needs no Phlex host.
  def html_to_md(inner, **opts)
    view = Class.new do
      define_method(:call) { "<div id=\"docs-content\">#{inner}</div>" }
    end.new
    described_class.new(view, **opts).to_md
  end

  it "extracts only #docs-content, ignoring surrounding chrome" do
    page = Class.new(Phlex::HTML) do
      def view_template
        div(class: "topbar") { plain "CHROME NAV" }
        div(id: "docs-content") { p { "Real content." } }
        div(class: "footer") { plain "CHROME FOOTER" }
      end
    end.new

    md = to_md(page)

    expect(md).to include("Real content.")
    expect(md).not_to include("CHROME NAV")
    expect(md).not_to include("CHROME FOOTER")
  end

  it "strips [data-md-skip] nodes (the '← Home' nav)" do
    page = docs_content do
      nav(data: { md_skip: true }) { a(href: "/") { "← Home" } }
      p { "Body text." }
    end

    md = to_md(page)

    expect(md).to include("Body text.")
    expect(md).not_to include("← Home")
  end

  describe "headings" do
    it "maps h1–h4 to #–####" do
      page = docs_content do
        h1 { "One" }
        h2 { "Two" }
        h3 { "Three" }
        h4 { "Four" }
      end

      md = to_md(page)

      expect(md).to include("# One")
      expect(md).to include("## Two")
      expect(md).to include("### Three")
      expect(md).to include("#### Four")
    end

    it "converts a DocsUI::Section heading to ## without its hover '#' decoration" do
      page = docs_content { render DocsUI::Section.new("Configuration") { p { "…" } } }

      md = to_md(page)

      expect(md).to include("## Configuration")
      # The Section heading's decorative "#" span (hover anchor) must not leak in.
      expect(md).not_to include("Configuration #")
      expect(md).not_to match(/Configuration\s+#\s*$/)
    end
  end

  describe "inline formatting" do
    it "emits bold, italic, and inline code" do
      md = html_to_md("<p>A <strong>bold</strong>, <em>italic</em>, <code>inline</code> word.</p>")

      expect(md).to include("**bold**")
      expect(md).to include("*italic*")
      expect(md).to include("`inline`")
    end

    it "round-trips inline code containing a backtick through GFM" do
      # A single-backtick fence closes at an interior backtick, corrupting the
      # span. The fence run must be longer than the longest run inside the text
      # (and padded when the content starts/ends with a backtick).
      require "commonmarker"
      md = html_to_md("<p>run <code>a`b</code> now.</p>")

      code_span = md[/`+ ?a`b ?`+/]
      expect(code_span).not_to be_nil
      expect(Commonmarker.to_html(code_span)).to include("<code>a`b</code>")
    end

    it "renders a link as [text](href)" do
      page = docs_content { p { a(href: "https://example.com/docs") { "the guide" } } }

      md = to_md(page)

      expect(md).to include("[the guide](https://example.com/docs)")
    end

    it "absolutizes a relative href against the base URL" do
      page = docs_content { p { a(href: "/docs/install") { "Install" } } }

      md = to_md(page, base_url: "https://acme.dev")

      expect(md).to include("[Install](https://acme.dev/docs/install)")
    end

    it "leaves a relative href relative when no base URL is given" do
      page = docs_content { p { a(href: "/docs/install") { "Install" } } }

      md = to_md(page)

      expect(md).to include("[Install](/docs/install)")
    end
  end

  describe "code blocks" do
    it "fences a DocsUI::Code(ruby) block with its language" do
      page = docs_content { render DocsUI::Code.new("puts 'hi'", lexer: :ruby) }

      md = to_md(page)

      expect(md).to include("```ruby")
      expect(md).to include("puts 'hi'")
      expect(md).to match(/```ruby\n.*puts 'hi'.*\n```/m)
    end

    it "emits a language-less fence for a plaintext block" do
      page = docs_content { render DocsUI::Code.new("just text", lexer: :nope) }

      md = to_md(page)

      # plaintext → a bare ``` fence (no language token).
      expect(md).to include("```\njust text\n```")
    end

    it "does not HTML-escape the source inside a fence" do
      page = docs_content { render DocsUI::Code.new("a < b && c > d", lexer: :ruby) }

      md = to_md(page)

      expect(md).to include("a < b && c > d")
      expect(md).not_to include("&lt;")
      expect(md).not_to include("&amp;")
    end

    it "does not leak a Code(filename:) title into the twin as a stray line" do
      page = docs_content { render DocsUI::Code.new("puts 1", lexer: :ruby, filename: "app.rb") }

      md = to_md(page)

      # The title bar is chrome — the fence must be bare, with no loose "app.rb"
      # paragraph above it.
      expect(md).to eq("```ruby\nputs 1\n```")
      expect(md).not_to include("app.rb")
    end
  end

  describe "callouts" do
    it "renders a DocsUI::Callout(:tip) as a > **Tip:** blockquote" do
      page = docs_content { render DocsUI::Callout.new(:tip) { "Use bundler." } }

      md = to_md(page)

      expect(md).to include("> **Tip:**")
      expect(md).to include("Use bundler.")
    end

    it "labels note and warning callouts" do
      note = to_md(docs_content { render DocsUI::Callout.new(:note) { "Noted." } })
      warn = to_md(docs_content { render DocsUI::Callout.new(:warning) { "Careful." } })

      expect(note).to include("> **Note:**")
      expect(warn).to include("> **Warning:**")
    end

    it "uses the author's title as the label and never fuses it into the body" do
      page = docs_content { render DocsUI::Callout.new(:tip, title: "Heads up") { "Body here." } }

      md = to_md(page)

      expect(md).to include("> **Heads up:** Body here.")
      expect(md).not_to include("Heads upBody here.")
    end
  end

  describe "lists" do
    it "renders a bullet list" do
      page = docs_content do
        ul do
          li { "one" }
          li { "two" }
        end
      end

      md = to_md(page)

      expect(md).to include("- one")
      expect(md).to include("- two")
    end

    it "renders an ordered list" do
      page = docs_content do
        ol do
          li { "first" }
          li { "second" }
        end
      end

      md = to_md(page)

      expect(md).to include("1. first")
      expect(md).to include("2. second")
    end

    it "indents a nested list under its parent item" do
      page = docs_content do
        ul do
          li do
            plain "parent"
            ul { li { "child" } }
          end
        end
      end

      md = to_md(page)

      # The nested item is indented (two spaces) beneath its parent bullet.
      expect(md).to match(/- parent\n\s{2,}- child/)
    end
  end

  describe "tables" do
    it "renders a DocsUI::PropTable as a GFM pipe table" do
      page = docs_content do
        render DocsUI::PropTable.new(
          [["brand", "String", '"Docs"', "Topbar heading."]]
        )
      end

      md = to_md(page)

      expect(md).to include("| Option | Type | Default | Description |")
      expect(md).to match(/\|\s*-+\s*\|/) # the header separator row
      expect(md).to include("brand")
      expect(md).to include("Topbar heading.")
    end

    it "keeps a rectangular GFM table when a body row has more cells than the header" do
      md = html_to_md(
        "<table>" \
        "<thead><tr><th>A</th><th>B</th></tr></thead>" \
        "<tbody><tr><td>1</td><td>2</td><td>3</td></tr></tbody>" \
        "</table>"
      )

      # Every line must declare the same number of columns as the widest row (3).
      pipe_counts = md.each_line.map { |line| line.count("|") }
      expect(pipe_counts.uniq).to eq([4])
    end
  end

  describe "misc block elements" do
    it "renders a blockquote" do
      page = docs_content { blockquote { p { "quoted" } } }

      md = to_md(page)

      expect(md).to include("> quoted")
    end

    it "renders a thematic break" do
      page = docs_content { hr }

      md = to_md(page)

      expect(md).to include("---")
    end

    it "renders an image with alt and src" do
      page = docs_content { img(src: "/logo.png", alt: "Logo") }

      md = to_md(page)

      expect(md).to include("![Logo](/logo.png)")
    end

    it "round-trips a Markdown image authored through DocsUI::Markdown" do
      page = docs_content { render DocsUI::Markdown.new("![Alt text](https://example.com/shot.png)") }

      md = to_md(page)

      expect(md).to include("![Alt text](https://example.com/shot.png)")
    end
  end

  describe "unknown / structural elements" do
    it "recurses into an unknown wrapper (text survives, wrapper dropped)" do
      page = docs_content do
        div(class: "mystery-wrapper") { p { "still here" } }
      end

      md = to_md(page)

      expect(md).to include("still here")
      expect(md).not_to include("mystery-wrapper")
    end

    it "drops script and style content entirely" do
      md = html_to_md("<style>body{color:red}</style><script>alert(1)</script><p>safe</p>")

      expect(md).to include("safe")
      expect(md).not_to include("alert(1)")
      expect(md).not_to include("color:red")
    end
  end

  describe "the full-page fixture (issue acceptance)" do
    let(:page) do
      docs_content do
        render DocsUI::Section.new("Getting started") do
          render DocsUI::Markdown.new("Install with **bundler**, then run the [server](/start).")
          render DocsUI::Code.new("bundle add docs-kit", lexer: :ruby)
          render DocsUI::Callout.new(:tip) { "Restart after editing config." }
          render DocsUI::PropTable.new([["brand", "String", '"Docs"', "Heading."]])
        end
      end
    end

    it "produces faithful GFM covering every vocabulary element" do
      md = to_md(page, base_url: "https://acme.dev")

      # One realistic page, every vocabulary element at once — aggregated so a
      # single failure still reports which element regressed.
      aggregate_failures do
        expect(md).to include("## Getting started")
        expect(md).to include("**bundler**")
        expect(md).to include("[server](https://acme.dev/start)")
        expect(md).to include("```ruby")
        expect(md).to include("bundle add docs-kit")
        expect(md).to include("> **Tip:**")
        expect(md).to include("| Option | Type | Default | Description |")
      end
    end
  end

  it "renders through a view context when one is given" do
    # The production path renders the Phlex view WITH a Rails view context (CSRF,
    # url helpers). Here we prove the seam: a view whose #call takes view_context:.
    view = Class.new do
      def call(view_context: nil)
        "[ctx:#{view_context}]<div id=\"docs-content\"><p>Rendered.</p></div>"
      end
    end.new

    md = described_class.new(view, view_context: "VC").to_md

    expect(md).to include("Rendered.")
  end

  it "returns empty string when there is no #docs-content region" do
    page = Class.new(Phlex::HTML) do
      def view_template = div(class: "no-anchor") { p { "orphan" } }
    end.new

    expect(described_class.new(page).to_md).to eq("")
  end
end
