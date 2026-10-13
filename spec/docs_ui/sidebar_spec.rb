# frozen_string_literal: true

RSpec.describe DocsUI::Sidebar do
  # The brand header reads only DocsKit.configuration (no Rails request), so — like
  # shell_spec's topbar-only render — we exercise just that fragment through a tiny
  # subclass whose view_template renders only the header section.
  let(:header_only) do
    Class.new(described_class) do
      def view_template = header_section
    end
  end

  describe "the brand link" do
    it "defaults the brand href to \"/\"" do
      html = header_only.new.call

      expect(html).to include('href="/"')
    end

    it "follows config.brand_href when a site overrides it" do
      DocsKit.configure { |c| c.brand_href = "/docs" }
      html = header_only.new.call

      expect(html).to include('href="/docs"')
    end
  end

  # The opt-in brand mark (config.brand_logo) — rendered in the header in place
  # of the text brand; the version badge survives either way. Absent config →
  # the text brand, byte-identical to before.
  describe "the brand mark" do
    it "renders the text brand with no svg by default (byte-compat)" do
      DocsKit.configure { |c| c.brand = "Docs" }
      html = header_only.new.call

      expect(html).to include("Docs")
      expect(html).not_to include("<svg")
    end

    it "renders the configured mark inside the brand anchor" do
      DocsKit.configure do |c|
        c.brand = "Docs"
        c.brand_logo = { paths: ["M0 0Z"] }
      end
      html = header_only.new.call

      expect(html).to include("<svg")
      expect(html).to include('d="M0 0Z"')
      expect(html).to include('aria-label="Docs"')
    end

    it "keeps the version badge next to the mark" do
      DocsKit.configure do |c|
        c.brand_logo = { svg: "M0 0Z" }
        c.version_badge = "v1.2"
      end
      html = header_only.new.call

      expect(html).to include("<svg")
      expect(html).to include("badge").and include("v1.2")
    end

    it "renders a callable brand's value, resolved per render" do
      current = +"Acme"
      DocsKit.configure do |c|
        c.brand = -> { current }
        c.nav_storage_key = "docs"
      end
      first = header_only.new.call
      current.replace("Globex")
      second = header_only.new.call

      expect(first).to include(">Acme</a>")
      expect(second).to include(">Globex</a>")
    end

    it "names the mark with a callable brand's value" do
      DocsKit.configure do |c|
        c.brand = -> { "Acme" }
        c.nav_storage_key = "docs"
        c.brand_logo = { svg: "M0 0Z" }
      end

      expect(header_only.new.call).to include('aria-label="Acme"')
    end
  end

  # The nav renders from config.nav_groups ({ heading => { subgroup => [NavItem] } }).
  # Icon-less items keep the render free of rails_icons; #current_path degrades to
  # nil outside a Rails request, so the full component renders standalone.
  def nav_item(href, label)
    DocsKit::NavItem.new(href: href, label: label)
  end

  describe "the nav with a single top-level heading" do
    before do
      DocsKit.configure do |c|
        c.nav = lambda {
          { "Documentation" => {
            "Getting started" => [nav_item("/docs/overview", "Overview")],
            "REST API" => [nav_item("/docs/accounts", "Accounts")]
          } }
        }
      end
    end

    let(:html) { described_class.new.call }

    it "drops the heading entirely" do
      expect(html).not_to include("Documentation")
    end

    it "renders the subgroups as top-level open collapsibles" do
      expect(html.scan(/<summary[^>]*>\s*([^<]+?)\s*</).flatten)
        .to contain_exactly("Getting started", "REST API")
    end

    it "renders every page link" do
      expect(html).to include('href="/docs/overview"').and include('href="/docs/accounts"')
    end

    it "server-renders every collapsible open (works with JS off)" do
      expect(html.scan("<details").count).to eq(html.scan("<details open").count)
    end
  end

  describe "the nav with multiple top-level headings" do
    before do
      DocsKit.configure do |c|
        c.nav = lambda {
          {
            "Docs" => { "Guide" => [nav_item("/docs/install", "Installation")] },
            "Demos" => { "Examples" => [nav_item("/demos/counter", "Counter")] }
          }
        }
      end
    end

    let(:html) { described_class.new.call }

    it "renders each heading as a static menu-title label, not a collapsible summary" do
      expect(html).to match(%r{<li class="[^"]*menu-title[^"]*">Docs</li>})
      expect(html).to match(%r{<li class="[^"]*menu-title[^"]*">Demos</li>})
      expect(html.scan(/<summary[^>]*>\s*([^<]+?)\s*</).flatten)
        .to contain_exactly("Guide", "Examples")
    end

    it "spaces headings apart from the group above" do
      expect(html).to match(/menu-title[^"]*mt-4|mt-4[^"]*menu-title/)
      expect(html).to include("first:mt-0")
    end

    it "keeps the subgroups collapsible and open" do
      expect(html.scan("<details").count).to eq(2)
      expect(html.scan("<details open").count).to eq(2)
    end

    it "skips a heading whose groups are empty" do
      DocsKit.configure do |c|
        c.nav = lambda {
          {
            "Docs" => { "Guide" => [nav_item("/docs/install", "Installation")] },
            "Empty" => {}
          }
        }
      end

      expect(html).not_to include("Empty")
      # One non-empty heading remains, so the single-heading rule applies.
      expect(html).not_to include("Docs</li>")
    end
  end
end
