# frozen_string_literal: true

# DocsUI::MetaTags emits the SEO/social <head> tags from DocsKit.configuration
# (+ .seo) and the per-page title/description. Unlike DocsUI::Shell it uses NO
# output helper that needs a live Rails request (no csrf/importmap), so it
# renders standalone with .call — the same isolated-render path a host without a
# request (a static build) would hit. The og:image is SITE content resolved
# through the site's asset pipeline (image_url); off a request there's no pipeline
# and no og:image is emitted (guarded like Shell#csp_nonce).
RSpec.describe DocsUI::MetaTags do
  def render_tags(title: "Installation", description: nil)
    described_class.new(title: title, description: description).call
  end

  # A subclass that reports a view context + resolves og_image through the asset
  # pipeline, mirroring how a real request renders. image_url is the Rails asset
  # helper: "og/og.png" → the digested, host-qualified /assets URL Propshaft
  # serves. The isolated suite has no view context, so we stub the seam (the same
  # technique shell_spec uses for csp_nonce) to prove the pipeline path.
  def render_with_pipeline(title: "Installation", description: nil)
    Class.new(described_class) do
      def view_context = :present
      # isolate og:image resolution from canonical/og:url
      def request? = false
      def image_url(path) = "https://d.example.com/assets/#{path.sub('.png', '-abc123.png')}"
    end.new(title: title, description: description).call
  end

  describe "the description meta" do
    it "emits <meta name=\"description\"> with the resolved page description" do
      html = render_tags(description: "Add the gem and render your first component.")

      expect(html).to include(
        '<meta name="description" content="Add the gem and render your first component.">'
      )
    end

    it "falls back to config.seo.description when the page passes none" do
      DocsKit.configure { |c| c.seo.description = "The shared Phlex chrome for docs sites." }
      html = render_tags(description: nil)

      expect(html).to include('content="The shared Phlex chrome for docs sites."')
    end

    it "omits the description meta when neither page nor site sets one" do
      html = render_tags(description: nil)

      expect(html).not_to include('name="description"')
    end
  end

  describe "the Open Graph block" do
    it "emits og:title as the full title (page · suffix), matching <title>" do
      DocsKit.configure { |c| c.brand = "Docs" }
      html = render_tags(title: "Installation")

      expect(html).to include('<meta property="og:title" content="Installation · Docs">')
    end

    it "emits og:site_name from config.brand and og:type from config.seo.og_type" do
      DocsKit.configure do |c|
        c.brand = "phlex-reactive"
        c.seo.og_type = "website"
      end
      html = render_tags

      expect(html).to include('<meta property="og:site_name" content="phlex-reactive">')
      expect(html).to include('<meta property="og:type" content="website">')
    end

    it "emits og:description when a description resolves" do
      html = render_tags(description: "Reactive Phlex components.")

      expect(html).to include('<meta property="og:description" content="Reactive Phlex components.">')
    end

    it "emits NO og:image when og_image is unset (the default — a valid card, no 404)" do
      html = render_tags

      expect(html).not_to include("og:image")
      expect(html).not_to include("twitter:image")
    end

    it "resolves a relative og_image through the asset pipeline (digested /assets URL)" do
      # The bug this guards: the raw config path "og/og.png" is NOT a served URL —
      # Propshaft serves the digested /assets/og/og-<digest>.png. image_url must
      # produce that, never the raw path (which 404s).
      DocsKit.configure { |c| c.seo.og_image = "og/og.png" }
      html = render_with_pipeline

      expect(html).to include('<meta property="og:image" content="https://d.example.com/assets/og/og-abc123.png">')
      expect(html).not_to include('content="og/og.png"') # never the raw, 404-ing path
    end

    it "leaves an absolute og_image URL untouched (no pipeline needed)" do
      DocsKit.configure { |c| c.seo.og_image = "https://cdn.example.com/card.png" }
      html = render_tags

      expect(html).to include('<meta property="og:image" content="https://cdn.example.com/card.png">')
    end

    it "emits no og:image for a relative path off a request (no pipeline to resolve it)" do
      # Off a request there's no asset pipeline, so a relative path can't be
      # resolved to a served URL — we emit nothing rather than a guessed-wrong URL.
      DocsKit.configure { |c| c.seo.og_image = "og/og.png" }
      html = render_tags

      expect(html).not_to include("og:image")
    end

    it "always emits a minimal, valid OG block even when a site configures nothing" do
      html = render_tags(title: "Installation")

      # title + type + site_name are always present (no broken empty tags).
      expect(html).to include('property="og:title"')
      expect(html).to include('property="og:type"')
      expect(html).to include('property="og:site_name"')
    end
  end

  describe "the Twitter Card block" do
    it "emits twitter:card from config.seo.twitter_card" do
      html = render_tags

      expect(html).to include('<meta name="twitter:card" content="summary_large_image">')
    end

    it "emits twitter:site and twitter:creator only when configured" do
      DocsKit.configure do |c|
        c.seo.twitter_site = "@docs"
        c.seo.twitter_creator = "@author"
      end
      html = render_tags

      expect(html).to include('<meta name="twitter:site" content="@docs">')
      expect(html).to include('<meta name="twitter:creator" content="@author">')
    end

    it "omits the twitter handles when unset" do
      html = render_tags

      expect(html).not_to include("twitter:site")
      expect(html).not_to include("twitter:creator")
    end
  end

  describe "canonical, favicon, robots, theme-color (all opt-in)" do
    it "emits <link rel=\"canonical\"> when a site_url is set" do
      DocsKit.configure { |c| c.seo.site_url = "https://docs.example.com/install" }
      html = render_tags

      expect(html).to include('<link rel="canonical" href="https://docs.example.com/install">')
    end

    it "omits canonical when no URL resolves (no site_url, no request)" do
      html = render_tags

      expect(html).not_to include('rel="canonical"')
    end

    it "emits <link rel=\"icon\"> only when config.seo.favicon is set" do
      html = render_tags
      expect(html).not_to include('rel="icon"')

      DocsKit.configure { |c| c.seo.favicon = "/favicon.ico" }
      expect(render_tags).to include('<link rel="icon" href="/favicon.ico">')
    end

    it "emits <meta name=\"robots\"> only when config.seo.robots is set" do
      html = render_tags
      expect(html).not_to include('name="robots"')

      DocsKit.configure { |c| c.seo.robots = "noindex, nofollow" }
      expect(render_tags).to include('<meta name="robots" content="noindex, nofollow">')
    end

    describe "robots under a version scope" do
      it "emits noindex, follow for an archived version (canonical untouched)" do
        archived = DocsKit::DocVersion.new(id: "1.0")

        html = DocsKit::Scope.with(version: archived) { render_tags }

        expect(html).to include('<meta name="robots" content="noindex, follow">')
        expect(html).not_to include('rel="canonical"')
      end

      it "keeps today's behavior for the current version in scope (regression pin)" do
        current = DocsKit::DocVersion.new(id: "1.1", current: true)

        html = DocsKit::Scope.with(version: current) { render_tags }

        expect(html).not_to include('name="robots"')
      end

      it "restores seo.robots for a version with noindex: false" do
        DocsKit.configure { |c| c.seo.robots = "index, follow" }
        opted_out = DocsKit::DocVersion.new(id: "1.0", noindex: false)

        html = DocsKit::Scope.with(version: opted_out) { render_tags }

        expect(html).to include('<meta name="robots" content="index, follow">')
      end
    end

    it "emits <meta name=\"theme-color\"> only when config.seo.theme_color is set" do
      html = render_tags
      expect(html).not_to include("theme-color")

      DocsKit.configure { |c| c.seo.theme_color = "#0f172a" }
      expect(render_tags).to include('<meta name="theme-color" content="#0f172a">')
    end
  end

  # With a live request (and no config.seo.site_url), canonical/og:url come from
  # the request URL. The isolated suite has no Rails request, so — like shell_spec
  # exercises csp_nonce — override the request seam with a subclass that reports a
  # request.
  describe "with a live request (site_url unset)" do
    let(:with_request) do
      Class.new(described_class) do
        def request? = true
        def request = Struct.new(:original_url).new("https://d.example.com/install")
      end
    end

    it "sets canonical and og:url from the request URL" do
      html = with_request.new(title: "Installation").call

      expect(html).to include('<link rel="canonical" href="https://d.example.com/install">')
      expect(html).to include('<meta property="og:url" content="https://d.example.com/install">')
    end
  end

  describe "escaping (config/page free text is Phlex-escaped, never raw)" do
    # The security property for an attribute value is that it cannot break OUT of
    # the double-quoted attribute — so " and & must be escaped. (A bare < inside a
    # quoted attribute is not a parse hazard and browsers keep it literal; Phlex,
    # correctly, does not escape it there.) These assert the value stays contained.
    it "escapes a quote in the description so it can't break out of the attribute" do
      html = render_tags(description: %(A "quoted" value))

      expect(html).to include("&quot;quoted&quot;").or include("&#34;quoted&#34;")
      # The raw double-quote never appears mid-value (it would end the attribute).
      expect(html).to include('content="A &quot;quoted&quot; value">')
        .or include('content="A &#34;quoted&#34; value">')
    end

    it "cannot break out of the og:title attribute even with an embedded quote" do
      # A brand containing a double-quote must be contained (escaped), or it would
      # terminate the attribute and inject markup.
      DocsKit.configure { |c| c.brand = %(Ac"me) }
      html = render_tags(title: "Intro")

      expect(html).to include('property="og:title"')
      expect(html).to include("&quot;").or include("&#34;")
      # The raw quote never appears mid-value (it would close the attribute early).
      expect(html).not_to include('content="Intro · Ac"me"')
    end
  end
end
