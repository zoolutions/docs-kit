# frozen_string_literal: true

# DocsKit::LlmsText builds the two AI-readable artifacts from the registry +
# config, with ZERO Rails: given a fake registry (the same #nav_items / #all
# duck type a real DocsKit::Registry exposes) and a Configuration, it produces
# the llms.txt index string and joins per-page Markdown into llms-full.txt. The
# controller (which owns the Rails view context) renders each page to Markdown
# and hands the [title, md] pairs to .full — so all the text shaping is tested
# here without booting Rails.
RSpec.describe DocsKit::LlmsText do
  # A NavItem-ish link: #href + #label (what #nav_items returns per group).
  def link(href:, label:)
    Struct.new(:href, :label, keyword_init: true).new(href:, label:)
  end

  # A page-ish entry: #title / #href / #view_class (what #all returns). A nil
  # view_class == an unwritten page, excluded everywhere.
  def entry(title:, href:, view_class:)
    Struct.new(:title, :href, :view_class, keyword_init: true).new(title:, href:, view_class:)
  end

  # A fake registry standing in for a DocsKit::Registry class: #nav_items groups
  # authored links; #all lists authored + unauthored entries in registry order.
  def registry(nav_items:, all: [])
    Class.new do
      define_singleton_method(:nav_items) { nav_items }
      define_singleton_method(:all) { all }
    end
  end

  let(:doc_registry) do
    registry(
      nav_items: {
        "Getting started" => [
          link(href: "/docs/overview", label: "Overview"),
          link(href: "/docs/installation", label: "Installation")
        ],
        "Reference" => [
          link(href: "/docs/components", label: "Components")
        ]
      }
    )
  end

  def configure(**opts)
    DocsKit.configure do |c|
      c.brand = opts.fetch(:brand, "docs-kit")
      c.tagline = opts[:tagline]
      c.nav_registries = opts.fetch(:nav_registries, { "Docs" => doc_registry })
    end
    DocsKit.configuration
  end

  describe ".index" do
    subject(:index) { described_class.index(configure(tagline: "Shared docs chrome."), base_url: "https://acme.dev") }

    it "opens with the brand as an H1" do
      expect(index).to start_with("# docs-kit\n")
    end

    it "renders the tagline as a blockquote under the H1" do
      expect(index).to include("\n> Shared docs chrome.\n")
    end

    it "renders each registry group as an H2 section" do
      expect(index).to include("## Getting started").and include("## Reference")
    end

    it "lists each authored page as a Markdown link to its absolute .md twin" do
      expect(index).to include("- [Overview](https://acme.dev/docs/overview.md)")
      expect(index).to include("- [Installation](https://acme.dev/docs/installation.md)")
      expect(index).to include("- [Components](https://acme.dev/docs/components.md)")
    end

    it "preserves registry order for groups and links" do
      expect(index.index("## Getting started")).to be < index.index("## Reference")
      expect(index.index("Overview")).to be < index.index("Installation")
    end

    it "renders each section as a tight bullet list (no blank line between bullets)" do
      # Section heading is followed immediately by its bullets, one per line.
      expect(index).to include(
        "## Getting started\n" \
        "- [Overview](https://acme.dev/docs/overview.md)\n" \
        "- [Installation](https://acme.dev/docs/installation.md)"
      )
    end

    context "when the tagline is nil (default)" do
      subject(:index) { described_class.index(configure(tagline: nil), base_url: "https://acme.dev") }

      it "omits the blockquote line entirely" do
        expect(index).not_to include(">")
        # H1 is immediately followed by the first section, no blank blockquote.
        expect(index).to start_with("# docs-kit\n\n## Getting started")
      end
    end

    context "with multiple registries" do
      subject(:index) do
        described_class.index(
          configure(nav_registries: { "Docs" => doc_registry, "API" => api_registry }),
          base_url: "https://acme.dev"
        )
      end

      let(:api_registry) do
        registry(nav_items: { "Endpoints" => [link(href: "/api/users", label: "Users")] })
      end

      it "emits every registry's groups in config order" do
        expect(index.index("## Getting started")).to be < index.index("## Endpoints")
        expect(index).to include("- [Users](https://acme.dev/api/users.md)")
      end
    end

    context "with an empty registry (all pages unwritten)" do
      subject(:index) do
        config = configure(nav_registries: { "Docs" => registry(nav_items: {}) })
        # Isolate the page-group behavior from the (gem-dependent) MCP block, which
        # legitimately adds its own `## MCP` section when the endpoint is live.
        allow(config).to receive(:mcp_enabled?).and_return(false)
        described_class.index(config, base_url: "https://acme.dev")
      end

      it "renders a valid index with no page sections (never an empty ## group)" do
        expect(index).to start_with("# docs-kit")
        expect(index).not_to include("##")
      end
    end

    it "does not require a base_url (relative .md links when omitted)" do
      index = described_class.index(configure(tagline: nil))

      expect(index).to include("- [Overview](/docs/overview.md)")
    end

    context "when the MCP endpoint is enabled" do
      subject(:index) do
        config = configure(tagline: nil)
        allow(config).to receive(:mcp_enabled?).and_return(true)
        described_class.index(config, base_url: "https://acme.dev")
      end

      it "advertises the MCP endpoint so agents can discover it" do
        expect(index).to include("## MCP")
        expect(index).to include("https://acme.dev/mcp")
      end

      it "puts the MCP block last (after the page sections)" do
        expect(index.index("## Getting started")).to be < index.index("## MCP")
      end

      it "uses a relative /mcp path when no base_url is given" do
        config = configure(tagline: nil)
        allow(config).to receive(:mcp_enabled?).and_return(true)

        expect(described_class.index(config)).to include("/mcp")
      end
    end

    context "when the MCP endpoint is disabled (default / no gem)" do
      subject(:index) do
        config = configure(tagline: nil)
        allow(config).to receive(:mcp_enabled?).and_return(false)
        described_class.index(config, base_url: "https://acme.dev")
      end

      it "omits the MCP advertisement entirely (byte-identical to before)" do
        expect(index).not_to include("## MCP")
        expect(index).not_to include("/mcp")
      end
    end
  end

  describe ".pages" do
    subject(:pages) { described_class.pages(config) }

    let(:written) { Object.new }
    let(:config) do
      configure(
        nav_registries: {
          "Docs" => registry(
            nav_items: {},
            all: [
              entry(title: "Overview", href: "/docs/overview", view_class: written),
              entry(title: "Unwritten", href: "/docs/unwritten", view_class: nil),
              entry(title: "Installation", href: "/docs/installation", view_class: written)
            ]
          )
        }
      )
    end

    it "returns only authored pages (a resolvable view_class), in registry order" do
      expect(pages.map(&:title)).to eq(%w[Overview Installation])
    end
  end

  describe ".full" do
    it "concatenates each page as an H1 title + its Markdown, separated by ---" do
      out = described_class.full(
        configure(tagline: nil),
        [["Overview", "Overview body."], ["Installation", "Install body."]]
      )

      expect(out).to eq(
        "# Overview\n\nOverview body.\n\n---\n\n# Installation\n\nInstall body."
      )
    end

    it "returns an empty string when there are no pages" do
      expect(described_class.full(configure, [])).to eq("")
    end
  end

  describe ".renderable_for" do
    it "uses #renderable when the page provides it (Registry v2, snapshot entries)" do
      page = Struct.new(:renderable).new(:the_renderable)

      expect(described_class.renderable_for(page)).to eq(:the_renderable)
    end

    it "falls back to view_class.new for a custom registry entry predating #renderable" do
      view = Class.new
      page = Struct.new(:view_class).new(view)

      expect(described_class.renderable_for(page)).to be_a(view)
    end
  end

  describe ".pages with configured versions" do
    let(:fixtures_root) { File.expand_path("../fixtures/snapshots", __dir__) }
    let(:live_view) { Class.new }

    before { DocsKit::Snapshot.reset_cache! }

    def versioned_config
      live = registry(
        nav_items: {},
        all: [entry(title: "Live", href: "/docs/live", view_class: live_view)]
      )
      config = configure(nav_registries: { "Docs" => live })
      DocsKit.configure do |c|
        c.snapshots_path = fixtures_root
        c.versions = [{ id: "1.1", current: true }, { id: "1.0" }]
      end
      config
    end

    it "enumerates the snapshot for an archived version argument" do
      config = versioned_config

      pages = described_class.pages(config, version: config.version("1.0"))

      expect(pages.map(&:slug)).to eq(%w[installation configuration])
      expect(pages.map(&:href)).to all(start_with("/1.0/docs/"))
    end

    it "keeps the live enumeration for the current version" do
      config = versioned_config

      pages = described_class.pages(config, version: config.version("1.1"))

      expect(pages.map(&:title)).to eq(%w[Live])
    end

    it "consults DocsKit::Scope when no version argument is given" do
      config = versioned_config

      DocsKit::Scope.with(version: config.version("1.0")) do
        expect(described_class.pages(config).map(&:slug)).to eq(%w[installation configuration])
      end
    end

    it "keeps the live enumeration with no scope and no argument" do
      config = versioned_config

      expect(described_class.pages(config).map(&:title)).to eq(%w[Live])
    end

    it "is unchanged on an unversioned site (the backwards-compat pin)" do
      live = registry(
        nav_items: {},
        all: [entry(title: "Live", href: "/docs/live", view_class: live_view)]
      )
      config = configure(nav_registries: { "Docs" => live })

      expect(described_class.pages(config).map(&:title)).to eq(%w[Live])
    end
  end
end
