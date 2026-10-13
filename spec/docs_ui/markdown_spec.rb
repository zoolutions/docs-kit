# frozen_string_literal: true

RSpec.describe DocsUI::Markdown do
  def render_md(source)
    described_class.new(source).call
  end

  it "wraps output in the Prose typography classes" do
    html = render_md("Just a paragraph.")

    # The wrapper reuses DocsUI::Prose's child-selector vocabulary so Markdown
    # prose is styled identically to hand-authored Prose.
    expect(html).to include("text-base-content/80")
    expect(html).to include("[&_p]:my-4")
    expect(html).to include("[&_code]:bg-base-300")
  end

  it "renders paragraphs, strong, em, and links" do
    html = render_md("A **bold** and *italic* word, plus a [link](https://example.com).")

    expect(html).to include("<p>")
    expect(html).to include("<strong>bold</strong>")
    expect(html).to include("<em>italic</em>")
    expect(html).to include('<a href="https://example.com">link</a>')
  end

  # A link href is only ever http(s), mailto:, tel:, or scheme-less (relative,
  # root-relative, protocol-relative, #anchor). Any other scheme (javascript:,
  # data:, vbscript:) renders the link text with no <a> — the same guard images
  # have, so page Markdown can't ship a script-bearing href.
  describe "link schemes" do
    it "drops the <a> for a javascript: href but keeps its text" do
      html = render_md("Click [here](javascript:alert(1)) now.")

      expect(html).to include("Click here now.")
      expect(html).not_to include("<a")
      expect(html).not_to include("javascript:")
    end

    it "drops a data: href and a whitespace-obfuscated scheme" do
      html = render_md("[a](data:text/html,x) [b](java&#9;script:alert(1)) [c](JAVASCRIPT:x)")

      expect(html).not_to include("<a")
      expect(html).not_to include("script:")
    end

    it "keeps http(s), mailto:, tel: and scheme-less hrefs" do
      hrefs = %w[http://x.io mailto:me@x.io tel:+1 /docs #top //cdn.io/x other.md]
      html = render_md(hrefs.map { |h| "[x](#{h})" }.join(" "))

      hrefs.each { |href| expect(html).to include(%(<a href="#{href}">)) }
    end
  end

  it "renders inline code as a <code> element (gets the [&_code] Prose treatment)" do
    html = render_md("Call `bundle install` first.")

    expect(html).to include("<code>bundle install</code>")
  end

  it "routes a fenced ```ruby block through DocsUI::Code (Rouge)" do
    html = render_md(<<~MD)
      ```ruby
      puts "hi"
      ```
    MD

    # DocsUI::Code's hallmarks: the .code-highlight wrapper and a Rouge token span.
    expect(html).to include("code-highlight")
    expect(html).to include("<pre>")
    # Rouge emits token classes on spans (e.g. .s2 for a double-quoted string).
    expect(html).to match(/<span class="[a-z0-9]+">/)
  end

  it "falls back to plaintext for an unknown fence language (never raises)" do
    expect do
      html = render_md(<<~MD)
        ```wut-lang
        not a real language
        ```
      MD
      expect(html).to include("code-highlight")
      expect(html).to include("not a real language")
    end.not_to raise_error
  end

  it "renders a fenced block with no language through Code as plaintext" do
    html = render_md(<<~MD)
      ```
      plain fenced text
      ```
    MD

    expect(html).to include("code-highlight")
    expect(html).to include("plain fenced text")
  end

  it "renders a GFM table with the kit's table classes" do
    html = render_md(<<~MD)
      | Name | Type |
      |------|------|
      | brand | String |
    MD

    expect(html).to include("<table")
    expect(html).to include("<th")
    expect(html).to include("<td")
    expect(html).to include("brand")
    expect(html).to include("String")
    # The first row is the header (GFM semantics).
    expect(html.index("Name")).to be < html.index("brand")
  end

  it "demotes headings — h1 becomes h3, h2 becomes h4, deeper stays h4" do
    html = render_md("# Big\n\n## Medium\n\n#### Deep")

    expect(html).to include("<h3>Big</h3>")
    expect(html).to include("<h4>Medium</h4>")
    expect(html).to include("<h4>Deep</h4>")
    expect(html).not_to include("<h1")
    expect(html).not_to include("<h2")
  end

  it "renders bullet and ordered lists" do
    html = render_md("- one\n- two\n\n1. first\n2. second")

    expect(html).to include("<ul>")
    expect(html).to include("<ol>")
    expect(html).to include("<li>one</li>")
    expect(html).to include("<li>first</li>")
  end

  it "renders a block quote and a thematic break" do
    html = render_md("> a quoted line\n\n---")

    expect(html).to include("<blockquote>")
    expect(html).to include("a quoted line")
    expect(html).to include("<hr")
  end

  it "renders GFM strikethrough" do
    html = render_md("This is ~~gone~~.")

    expect(html).to include("<del>gone</del>")
  end

  it "drops raw HTML — <script> never appears in the output" do
    html = render_md("Before <script>alert(1)</script> after.")

    # The executable tag is dropped (AST html_inline nodes are skipped). The
    # inner text may remain as inert, escaped text — but never as a live tag.
    expect(html).not_to include("<script>")
    expect(html).not_to include("</script>")
    expect(html).to include("Before")
    expect(html).to include("after")
  end

  it "drops a raw HTML block entirely" do
    html = render_md("Text.\n\n<div onclick=\"evil()\">boom</div>")

    expect(html).not_to include("<div onclick")
    expect(html).not_to include("onclick")
    expect(html).to include("Text.")
  end

  it "renders interpolation-looking text literally (Phlex escaping, no html_safe)" do
    # A literal that LOOKS like Ruby interpolation but is plain author text.
    literal = ["#", "{user}"].join
    html = render_md("Use #{literal} in a template.")

    expect(html).to include(literal)
  end

  it "escapes HTML-special characters in author text" do
    html = render_md("A < B && C > D")

    expect(html).to include("&lt;")
    expect(html).to include("&gt;")
    expect(html).to include("&amp;")
  end

  it "renders an empty wrapper for nil or empty source (never raises)" do
    expect { described_class.new(nil).call }.not_to raise_error
    expect(described_class.new("").call).to include("</div>")
  end

  it "normalizes a non-UTF-8 source (commonmarker requires UTF-8)" do
    ascii = "Plain ASCII prose.".encode(Encoding::US_ASCII)

    expect { render_md(ascii) }.not_to raise_error
    expect(render_md(ascii)).to include("Plain ASCII prose.")
  end

  it "renders a header-only table without a body (no drop error)" do
    html = render_md("| a | b |\n|---|---|")

    expect(html).to include("<table")
    expect(html).to include("<th")
    expect(html).not_to include("<td")
  end

  # ![alt](src "title") — an <img> whose src resolves through the site's asset
  # pipeline (image_path) for a relative path, verbatim for an absolute one.
  describe "images" do
    # A subclass that reports a view context and resolves image_path the way
    # Propshaft does — the seam meta_tags_spec stubs for image_url.
    def render_with_pipeline(source)
      Class.new(described_class) do
        def view_context = :present
        def image_path(path) = "/assets/#{path.sub('.png', '-abc123.png')}"
      end.new(source).call
    end

    it "resolves a relative src through the asset pipeline" do
      html = render_with_pipeline("![Alt text](dir/shot.png)")

      expect(html).to include('src="/assets/dir/shot-abc123.png"')
      expect(html).to include('alt="Alt text"')
      expect(html).to include('loading="lazy"')
    end

    it "uses the relative src verbatim with no view context (isolated render)" do
      html = render_md("![Alt text](dir/shot.png)")

      expect(html).to include('<img src="dir/shot.png"')
    end

    it "keeps an absolute, protocol-relative or root-relative URL verbatim" do
      html = render_with_pipeline(<<~MD)
        ![a](https://example.com/a.png) ![b](//cdn.example.com/b.png) ![c](/static/c.png)
      MD

      expect(html).to include('src="https://example.com/a.png"')
      expect(html).to include('src="//cdn.example.com/b.png"')
      expect(html).to include('src="/static/c.png"')
      expect(html).not_to include("abc123")
    end

    it "builds the alt from the description's text, dropping inline markup" do
      html = render_md("![*Emphasised* `alt`](a.png)")

      expect(html).to include('alt="Emphasised alt"')
      expect(html).not_to include("<em>")
    end

    it "keeps a word boundary where the description breaks across lines" do
      html = render_md("![first line\nsecond line](a.png)")

      expect(html).to include('alt="first line second line"')
    end

    it "renders an image title as the title attribute" do
      html = render_md('![a](a.png "The caption")')

      expect(html).to include('title="The caption"')
    end

    it "omits the title attribute when the image has none" do
      expect(render_md("![a](a.png)")).not_to include("title=")
    end

    it "styles the image like the kit's bordered boxes" do
      expect(render_md("![a](a.png)")).to include(DocsUI::Markdown::IMAGE_CLASSES)
    end

    it "escapes the alt text (Phlex attribute escaping)" do
      html = render_md('![say "hi" <b>](a.png)')

      expect(html).to include('alt="say &quot;hi&quot;')
      expect(html).not_to include("<b>")
    end

    %w[javascript:alert(1) JaVaScRiPt:alert(1) data:image/png;base64,AAAA vbscript:x].each do |src|
      it "renders no <img> for an unsafe #{src.split(':').first} source" do
        html = render_md("![x](#{src})")

        expect(html).not_to include("<img")
        expect(html).not_to include(src)
      end
    end

    it "renders no <img> for a scheme hidden behind a control character" do
      html = render_md("![x](<java\tscript:alert(1)>)")

      expect(html).not_to include("<img")
    end
  end

  # DocsUI::Markdown.inline renders inline markdown for a [:md, "…"] table cell:
  # no Prose wrapper div, and a single top-level paragraph is unwrapped so its
  # inline children sit directly in the surrounding element.
  describe ".inline" do
    def render_inline(source)
      described_class.inline(source).call
    end

    it "emits inline children without a <p> or the Prose wrapper div" do
      html = render_inline("a **bold** note")

      expect(html).to include("a <strong>bold</strong> note")
      expect(html).not_to include("<p>")
      expect(html).not_to include("text-base-content/80") # no Prose wrapper
    end

    it "keeps a soft line break within a paragraph as a single space" do
      html = render_inline("line one\nline two")

      expect(html).to include("line one line two")
    end

    it "separates multiple top-level paragraphs instead of fusing their text" do
      html = render_inline("para one\n\npara two")

      # Without a separator the words would glue into "onepara".
      expect(html).not_to include("onepara")
      expect(html).to include("para one")
      expect(html).to include("para two")
    end

    it "renders an empty string without raising" do
      expect { render_inline("") }.not_to raise_error
    end
  end

  # The `md(source)` helper lives in DocsUI::PageHelpers (mixed into DocsUI::Page).
  # Page itself needs a Rails view context (Shell composes CSRF/url helpers) and
  # can't load standalone, so exercise the REAL helper module through a bare Phlex
  # host that includes it plus the same DocsUI kit a Page does.
  describe "the DocsUI::Page#md helper delegation" do
    def render_md_helper(source)
      md_source = source
      Class.new(Phlex::HTML) do
        include DocsUI
        include DocsUI::PageHelpers

        define_method(:view_template) { md(md_source) }
      end.new.call
    end

    it "renders Prose-styled Markdown from a page body" do
      html = render_md_helper("A **markdown** paragraph.")

      expect(html).to include("text-base-content/80") # the Prose wrapper classes
      expect(html).to include("<strong>markdown</strong>")
    end
  end
end
