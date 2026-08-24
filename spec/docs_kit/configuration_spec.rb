# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe DocsKit::Configuration do
  describe "#brand_href" do
    it "defaults to \"/\" (the topbar brand link's current target)" do
      expect(described_class.new.brand_href).to eq("/")
    end

    it "is overridable so a site can point the brand link elsewhere (e.g. /docs)" do
      DocsKit.configure { |c| c.brand_href = "/docs" }

      expect(DocsKit.configuration.brand_href).to eq("/docs")
    end
  end

  describe "#app_link" do
    it "defaults to nil (no App Home link renders)" do
      expect(described_class.new.app_link).to be_nil
    end

    it "normalizes a symbol-keyed Hash into a DocsKit::TopbarLink" do
      DocsKit.configure { |c| c.app_link = { href: "/", label: "Back to the app" } }

      link = DocsKit.configuration.app_link
      expect(link).to be_a(DocsKit::TopbarLink)
      expect(link.href).to eq("/")
      expect(link.label).to eq("Back to the app")
    end

    it "normalizes a string-keyed Hash (a YAML/JSON-loaded config) the same way" do
      DocsKit.configure { |c| c.app_link = { "href" => "/app", "label" => "App Home" } }

      link = DocsKit.configuration.app_link
      expect(link.href).to eq("/app")
      expect(link.label).to eq("App Home")
    end

    it "passes an existing DocsKit::TopbarLink through unchanged" do
      value = DocsKit::TopbarLink.new(href: "/", label: "Back to the app")
      DocsKit.configure { |c| c.app_link = value }

      expect(DocsKit.configuration.app_link).to be(value)
    end
  end

  describe "#brand_logo" do
    it "defaults to nil (the chrome renders the text brand, byte-identical to before)" do
      expect(described_class.new.brand_logo).to be_nil
    end

    it "normalizes a Hash into a DocsKit::BrandLogo" do
      DocsKit.configure { |c| c.brand_logo = { paths: ["M0 0Z"], label: "Acme" } }

      logo = DocsKit.configuration.brand_logo
      expect(logo).to be_a(DocsKit::BrandLogo)
      expect(logo.paths).to eq(["M0 0Z"])
    end

    it "memoizes the normalized value (a file: mark must not re-validate per render)" do
      DocsKit.configure { |c| c.brand_logo = { svg: "M0 0Z" } }

      config = DocsKit.configuration
      first = config.brand_logo

      expect(config.brand_logo).to be(first)
    end

    it "re-normalizes after reassignment" do
      config = described_class.new
      config.brand_logo = { svg: "M0 0Z" }
      first = config.brand_logo
      config.brand_logo = { svg: "M1 1Z" }

      expect(config.brand_logo).not_to be(first)
      expect(config.brand_logo.svg).to eq("M1 1Z")
    end

    it "raises on first read of a malformed value (loud, never a silently broken header)" do
      config = described_class.new
      config.brand_logo = {}

      expect { config.brand_logo }.to raise_error(ArgumentError, /brand_logo/)
    end
  end

  describe "#topbar_brand" do
    it "defaults to :always (strict byte-compat — the topbar brand renders everywhere)" do
      expect(described_class.new.topbar_brand).to eq(:always)
    end

    it "accepts :mobile_only (the desktop dedup — the sidebar brand already shows at lg:)" do
      DocsKit.configure { |c| c.topbar_brand = :mobile_only }

      expect(DocsKit.configuration.topbar_brand).to eq(:mobile_only)
    end

    it "accepts the string form (a YAML/ENV-loaded config)" do
      DocsKit.configure { |c| c.topbar_brand = "mobile_only" }

      expect(DocsKit.configuration.topbar_brand).to eq(:mobile_only)
    end

    it "raises on an unknown mode, naming the knob" do
      expect { described_class.new.topbar_brand = :desktop_only }
        .to raise_error(ArgumentError, /topbar_brand/)
    end
  end

  describe "#tagline" do
    it "defaults to nil (the llms.txt blockquote line is omitted)" do
      expect(described_class.new.tagline).to be_nil
    end

    it "is overridable so a site sets its llms.txt summary" do
      DocsKit.configure { |c| c.tagline = "The shared Phlex chrome for docs sites." }

      expect(DocsKit.configuration.tagline).to eq("The shared Phlex chrome for docs sites.")
    end
  end

  describe "#seo" do
    it "returns a DocsKit::SeoConfig with backwards-safe defaults" do
      seo = described_class.new.seo

      expect(seo).to be_a(DocsKit::SeoConfig)
      expect(seo.description).to be_nil
      expect(seo.og_image).to be_nil
    end

    it "memoizes the same instance so a `c.seo.x = ...` block sticks" do
      config = described_class.new
      first = config.seo

      # The same object every call — a `c.seo.description = ...` block mutates the
      # instance the Shell later reads (not a throwaway rebuilt per access).
      expect(config.seo).to be(first)
    end

    it "is configured via the nested block (c.seo.description = ...)" do
      DocsKit.configure { |c| c.seo.description = "The shared Phlex chrome for docs." }

      expect(DocsKit.configuration.seo.description).to eq("The shared Phlex chrome for docs.")
    end
  end

  describe "#landing" do
    it "returns a DocsKit::LandingConfig with backwards-safe defaults" do
      landing = described_class.new.landing

      expect(landing).to be_a(DocsKit::LandingConfig)
      expect(landing.doc_index?).to be(true)
      expect(landing.features).to eq([])
    end

    it "memoizes the same instance so a `c.landing.x = ...` block sticks" do
      config = described_class.new
      first = config.landing

      expect(config.landing).to be(first)
    end

    it "is configured via the nested block (c.landing.title = ...)" do
      DocsKit.configure { |c| c.landing.title = "The Acme API" }

      expect(DocsKit.configuration.landing.title).to eq("The Acme API")
    end
  end

  describe "#page_markdown_action" do
    it "defaults to true (every page shows the 'Markdown' affordance)" do
      expect(described_class.new.page_markdown_action).to be(true)
    end

    it "is overridable so a site can opt out" do
      DocsKit.configure { |c| c.page_markdown_action = false }

      expect(DocsKit.configuration.page_markdown_action).to be(false)
    end
  end

  describe "#search" do
    it "defaults to true (the topbar search form renders)" do
      expect(described_class.new.search).to be(true)
    end

    it "is overridable so a site can hide search site-wide" do
      DocsKit.configure { |c| c.search = false }

      expect(DocsKit.configuration.search).to be(false)
    end
  end

  describe "#mcp" do
    it "defaults to true (the endpoint is on wherever the mcp gem + route are present)" do
      expect(described_class.new.mcp).to be(true)
    end

    it "is overridable so a site with the gem installed can still disable the endpoint" do
      DocsKit.configure { |c| c.mcp = false }

      expect(DocsKit.configuration.mcp).to be(false)
    end
  end

  describe "#mcp_enabled?" do
    # The endpoint requires BOTH the config toggle on AND the optional `mcp` gem
    # present — the same "toggle AND capability" shape as #search_enabled?. The
    # suite loads `mcp` (dev/test group), so defined?(MCP) is true here.
    it "is true when #mcp is on and the mcp gem is loaded" do
      skip "mcp gem not loaded in this run" unless defined?(MCP)

      expect(described_class.new.mcp_enabled?).to be(true)
    end

    it "is false when #mcp is off, even with the gem present" do
      DocsKit.configure { |c| c.mcp = false }

      expect(DocsKit.configuration.mcp_enabled?).to be(false)
    end

    it "is false when the mcp gem is absent, even with #mcp on" do
      config = described_class.new
      allow(config).to receive(:mcp_gem_present?).and_return(false)

      expect(config.mcp_enabled?).to be(false)
    end
  end

  describe "#search_path" do
    it "defaults to \"/docs/search\" (the route the generator draws)" do
      expect(described_class.new.search_path).to eq("/docs/search")
    end

    it "is overridable so a site can mount search elsewhere" do
      DocsKit.configure { |c| c.search_path = "/guides/search" }

      expect(DocsKit.configuration.search_path).to eq("/guides/search")
    end
  end

  describe "#search_shortcuts" do
    it "defaults to \"/\" and the platform \"mod+k\" chord" do
      shortcuts = described_class.new.search_shortcuts

      expect(shortcuts.map(&:key)).to eq(%w[/ k])
      # The chord is the platform modifier so one config works on every OS.
      slash, modk = shortcuts
      expect(slash.mod?).to be(false)
      expect(modk.mod?).to be(true)
    end

    it "returns parsed DocsKit::Shortcut objects, not raw strings" do
      expect(described_class.new.search_shortcuts).to all(be_a(DocsKit::Shortcut))
    end

    it "accepts a site's own list of shortcut strings" do
      DocsKit.configure { |c| c.search_shortcuts = ["mod+k", "s", "ctrl+shift+f"] }

      shortcuts = DocsKit.configuration.search_shortcuts
      expect(shortcuts.map(&:key)).to eq(%w[k s f])
      expect(shortcuts.last.shift?).to be(true)
    end

    it "drops entries that don't parse (a modifier-only string)" do
      DocsKit.configure { |c| c.search_shortcuts = ["/", "mod+", ""] }

      expect(DocsKit.configuration.search_shortcuts.map(&:key)).to eq(%w[/])
    end

    it "is empty when a site clears the list" do
      DocsKit.configure { |c| c.search_shortcuts = [] }

      expect(DocsKit.configuration.search_shortcuts).to eq([])
    end
  end

  describe "#search_enabled?" do
    it "is true by default (search on + a path set)" do
      expect(described_class.new.search_enabled?).to be(true)
    end

    it "is false when search is disabled" do
      DocsKit.configure { |c| c.search = false }

      expect(DocsKit.configuration.search_enabled?).to be(false)
    end

    it "is false when search_path is blanked (nothing to submit to)" do
      DocsKit.configure { |c| c.search_path = "" }

      expect(DocsKit.configuration.search_enabled?).to be(false)
    end
  end

  describe "#code_theme_dark" do
    it "defaults to nil (single-theme behavior, fully backwards compatible)" do
      expect(described_class.new.code_theme_dark).to be_nil
    end

    it "is overridable with a Rouge theme for dark daisyUI themes" do
      DocsKit.configure { |c| c.code_theme_dark = "Rouge::Themes::Monokai" }

      expect(DocsKit.configuration.code_theme_dark).to eq("Rouge::Themes::Monokai")
    end
  end

  describe "#code_theme_dark_class" do
    it "returns nil when code_theme_dark is unset" do
      expect(described_class.new.code_theme_dark_class).to be_nil
    end

    it "resolves a String theme name to the Rouge theme class" do
      DocsKit.configure { |c| c.code_theme_dark = "Rouge::Themes::Monokai" }

      expect(DocsKit.configuration.code_theme_dark_class).to eq(Rouge::Themes::Monokai)
    end

    it "passes a Rouge theme Class through unchanged" do
      DocsKit.configure { |c| c.code_theme_dark = Rouge::Themes::Monokai }

      expect(DocsKit.configuration.code_theme_dark_class).to eq(Rouge::Themes::Monokai)
    end

    it "degrades to nil (no dark CSS) when the theme name doesn't resolve, rather than raising" do
      DocsKit.configure { |c| c.code_theme_dark = "Rouge::Themes::Nope" }

      expect { DocsKit.configuration.code_theme_dark_class }.not_to raise_error
      expect(DocsKit.configuration.code_theme_dark_class).to be_nil
    end
  end

  describe "#code_theme_class" do
    it "resolves a String theme name to the Rouge theme class" do
      DocsKit.configure { |c| c.code_theme = "Rouge::Themes::Github" }

      expect(DocsKit.configuration.code_theme_class).to eq(Rouge::Themes::Github)
    end

    it "degrades to the default theme when a typo'd theme name doesn't resolve (not a crash)" do
      DocsKit.configure { |c| c.code_theme = "Rouge::Themes::Doesnotexist" }

      expect { DocsKit.configuration.code_theme_class }.not_to raise_error
      expect(DocsKit.configuration.code_theme_class).to eq(Rouge::Themes::Monokai)
    end
  end

  describe "#version_badge_text" do
    it "returns nil when unset" do
      expect(described_class.new.version_badge_text).to be_nil
    end

    it "calls a lambda value" do
      DocsKit.configure { |c| c.version_badge = -> { "v1.2.3" } }

      expect(DocsKit.configuration.version_badge_text).to eq("v1.2.3")
    end

    it "renders a plain String value (not only a callable)" do
      DocsKit.configure { |c| c.version_badge = "v1.2" }

      expect(DocsKit.configuration.version_badge_text).to eq("v1.2")
    end
  end

  describe "#dark_themes" do
    it "defaults to the built-in daisyUI dark theme names" do
      expect(described_class.new.dark_themes).to eq(DocsKit::Configuration::DEFAULT_DARK_THEMES)
    end

    it "ships a frozen default constant so it can't be mutated in place" do
      expect(DocsKit::Configuration::DEFAULT_DARK_THEMES).to be_frozen
    end

    it "is overridable so a site can name its custom dark themes (e.g. zazu-dark)" do
      DocsKit.configure { |c| c.dark_themes = %w[zazu-dark] }

      expect(DocsKit.configuration.dark_themes).to eq(%w[zazu-dark])
    end
  end

  describe "#dark_themes_shipped" do
    it "intersects dark_themes with themes so only shipped themes generate CSS" do
      DocsKit.configure do |c|
        c.themes = %w[light dark synthwave]
      end

      # dark + synthwave are dark daisyUI themes AND shipped; light is not dark.
      expect(DocsKit.configuration.dark_themes_shipped).to eq(%w[dark synthwave])
    end

    it "preserves theme declaration order (not the dark-list order)" do
      DocsKit.configure do |c|
        c.themes = %w[synthwave light dark]
      end

      expect(DocsKit.configuration.dark_themes_shipped).to eq(%w[synthwave dark])
    end

    it "is empty when no shipped theme is a dark theme" do
      DocsKit.configure { |c| c.themes = %w[light retro] }

      expect(DocsKit.configuration.dark_themes_shipped).to eq([])
    end
  end

  describe "#icon_library" do
    it "defaults to lucide (matching the lucide icon names docs-kit ships)" do
      expect(described_class.new.icon_library).to eq("lucide")
    end

    it "is overridable via DocsKit.configure so a site can pin the chrome library" do
      DocsKit.configure { |c| c.icon_library = "phosphor" }

      expect(DocsKit.configuration.icon_library).to eq("phosphor")
    end
  end

  # A registry-v2 stub: a class with the .nav_items API the config derives nav
  # from. Two authored pages in one group.
  def registry_stub
    Class.new do
      def self.nav_items
        { "Guide" => [DocsKit::NavItem.new(href: "/docs/installation", label: "Installation")] }
      end
    end
  end

  describe "#nav_registries" do
    it "defaults to an empty Hash" do
      expect(described_class.new.nav_registries).to eq({})
    end

    it "is overridable so a site maps a heading to its registry" do
      reg = registry_stub
      DocsKit.configure { |c| c.nav_registries = { "Docs" => reg } }

      expect(DocsKit.configuration.nav_registries).to eq({ "Docs" => reg })
    end
  end

  describe "#nav_groups" do
    it "derives from nav_registries when no explicit nav lambda is set" do
      reg = registry_stub
      DocsKit.configure { |c| c.nav_registries = { "Docs" => reg } }

      groups = DocsKit.configuration.nav_groups
      expect(groups.keys).to eq(%w[Docs])
      expect(groups["Docs"]["Guide"].map(&:label)).to eq(%w[Installation])
    end

    it "drops a registry heading whose pages are all unauthored (empty nav_items)" do
      empty = Class.new { def self.nav_items = {} }
      reg = registry_stub
      DocsKit.configure { |c| c.nav_registries = { "Empty" => empty, "Docs" => reg } }

      expect(DocsKit.configuration.nav_groups.keys).to eq(%w[Docs])
    end

    it "lets an explicit nav lambda win over nav_registries (backwards compatible)" do
      reg = registry_stub
      DocsKit.configure do |c|
        c.nav_registries = { "Docs" => reg }
        c.nav = -> { { "Custom" => { "Group" => [] } } }
      end

      expect(DocsKit.configuration.nav_groups.keys).to eq(%w[Custom])
    end

    it "returns an empty Hash when neither nav nor nav_registries is set" do
      expect(described_class.new.nav_groups).to eq({})
    end

    it "honors an explicitly-assigned nav that resolves to empty (not object identity)" do
      # A site that deliberately sets an empty nav lambda must WIN over
      # nav_registries — the 'is nav set?' test is explicit assignment, not
      # `equal?(DEFAULT_NAV)` (any lambda is a different object).
      reg = registry_stub
      DocsKit.configure do |c|
        c.nav_registries = { "Docs" => reg }
        c.nav = -> { {} }
      end

      expect(DocsKit.configuration.nav_groups).to eq({})
    end
  end

  describe "#api_base_url" do
    it "defaults to a neutral example host" do
      expect(described_class.new.api_base_url).to eq("https://api.example.com")
    end

    it "is overridable so a site points snippets at its own host" do
      DocsKit.configure { |c| c.api_base_url = "https://api.acme.test" }

      expect(DocsKit.configuration.api_base_url).to eq("https://api.acme.test")
    end
  end

  describe "#api_auth_header" do
    it "defaults to nil (no auth line in generated snippets)" do
      expect(described_class.new.api_auth_header).to be_nil
    end

    it "is overridable with the site's example Authorization header" do
      DocsKit.configure { |c| c.api_auth_header = "Authorization: Bearer sk_live_..." }

      expect(DocsKit.configuration.api_auth_header).to eq("Authorization: Bearer sk_live_...")
    end
  end

  describe "#api_clients" do
    it "ships four default clients in a stable order" do
      expect(described_class.new.api_clients.keys).to eq(%i[curl javascript ruby python])
    end

    it "exposes each default as a DocsKit::ApiClient with a label, lexer and template" do
      curl = described_class.new.api_clients[:curl]

      expect(curl).to be_a(DocsKit::ApiClient)
      expect(curl.label).to eq("cURL")
      expect(curl.lexer).to eq(:curl)
      expect(curl.template).to respond_to(:call)
    end

    it "merges site clients over the defaults, appending new ones in declaration order" do
      cli = DocsKit::ApiClient.new(label: "CLI", lexer: :shell, template: ->(_req) { "acme do" })
      DocsKit.configure { |c| c.api_clients = { cli: cli } }

      keys = DocsKit.configuration.api_clients.keys
      expect(keys).to eq(%i[curl javascript ruby python cli])
      expect(DocsKit.configuration.api_clients[:cli]).to eq(cli)
    end

    it "lets a site override a default client by reusing its token" do
      sdk_ruby = DocsKit::ApiClient.new(label: "Ruby", lexer: :ruby, template: ->(_req) { "Acme.new" })
      DocsKit.configure { |c| c.api_clients = { ruby: sdk_ruby } }

      clients = DocsKit.configuration.api_clients
      expect(clients.keys).to eq(%i[curl javascript ruby python]) # order preserved, no dup
      expect(clients[:ruby]).to eq(sdk_ruby)
    end
  end

  describe "#openapi" do
    let(:yaml_path) { File.expand_path("../fixtures/openapi.yaml", __dir__) }

    it "defaults to nil (the bridge is off; sites keep working unchanged)" do
      expect(described_class.new.openapi).to be_nil
    end

    it "accepts a String path" do
      DocsKit.configure { |c| c.openapi = yaml_path }

      expect(DocsKit.configuration.openapi).to eq(yaml_path)
    end

    it "accepts a Pathname" do
      DocsKit.configure { |c| c.openapi = Pathname.new(yaml_path) }

      expect(DocsKit.configuration.openapi).to eq(Pathname.new(yaml_path))
    end

    it "accepts an already-parsed Hash" do
      hash = YAML.safe_load_file(yaml_path, aliases: true, permitted_classes: [Date, Time])
      DocsKit.configure { |c| c.openapi = hash }

      expect(DocsKit.configuration.openapi).to eq(hash)
    end
  end

  describe "#topbar_links" do
    it "defaults to an empty array (no topbar links, byte-identical to before)" do
      expect(described_class.new.topbar_links).to eq([])
    end

    it "normalizes symbol-keyed Hashes into TopbarLink value objects" do
      DocsKit.configure do |c|
        c.topbar_links = [{ href: "https://github.com/me/repo", label: "GitHub", icon: :github }]
      end

      links = DocsKit.configuration.topbar_links
      expect(links.length).to eq(1)
      expect(links.first).to be_a(DocsKit::TopbarLink)
      expect(links.first.href).to eq("https://github.com/me/repo")
      expect(links.first.label).to eq("GitHub")
      expect(links.first.icon).to eq(:github)
    end

    it "accepts already-built TopbarLink objects unchanged" do
      link = DocsKit::TopbarLink.new(href: "/x", label: "X", icon: :x)
      DocsKit.configure { |c| c.topbar_links = [link] }

      expect(DocsKit.configuration.topbar_links).to eq([link])
    end

    it "preserves declaration order across mixed inputs" do
      DocsKit.configure do |c|
        c.topbar_links = [
          { href: "/a", label: "A", icon: :github },
          { href: "/b", label: "B", icon: :discord }
        ]
      end

      expect(DocsKit.configuration.topbar_links.map(&:label)).to eq(%w[A B])
    end

    it "coerces a nil assignment back to an empty array" do
      DocsKit.configure { |c| c.topbar_links = nil }

      expect(DocsKit.configuration.topbar_links).to eq([])
    end
  end

  describe "#openapi_document" do
    let(:yaml_path) { File.expand_path("../fixtures/openapi.yaml", __dir__) }

    it "returns a Document when c.openapi is set" do
      DocsKit.configure { |c| c.openapi = yaml_path }

      expect(DocsKit.configuration.openapi_document).to be_a(DocsKit::OpenApi::Document)
    end

    it "memoizes the loaded Document (same instance across reads)" do
      DocsKit.configure { |c| c.openapi = yaml_path }
      config = DocsKit.configuration
      first = config.openapi_document

      expect(config.openapi_document).to be(first)
    end

    it "reloads when the source file's mtime changes" do
      tmp = File.join(Dir.mktmpdir, "openapi.yaml")
      FileUtils.cp(yaml_path, tmp)
      DocsKit.configure { |c| c.openapi = tmp }
      config = DocsKit.configuration
      first = config.openapi_document

      # Rewrite with a changed mtime a second into the future (mtime resolution).
      FileUtils.touch(tmp, mtime: File.mtime(tmp) + 2)

      expect(config.openapi_document).not_to be(first)
    end

    it "raises a DocsKit::Error naming c.openapi when read while unset" do
      expect { described_class.new.openapi_document }
        .to raise_error(DocsKit::Error, /c\.openapi/)
    end
  end

  describe "#versions" do
    it "defaults to [] (an unversioned site is byte-identical to before)" do
      expect(described_class.new.versions).to eq([])
    end

    it "normalizes configured Hashes into DocVersion value objects" do
      DocsKit.configure do |c|
        c.versions = [
          { id: "1.1", current: true },
          { "id" => "1.0", "ref" => "v1.0.0" }
        ]
      end

      versions = DocsKit.configuration.versions
      expect(versions).to all(be_a(DocsKit::DocVersion))
      expect(versions.map(&:id)).to eq(%w[1.1 1.0])
      expect(versions.last.ref).to eq("v1.0.0")
    end

    it "passes DocVersion instances through unchanged" do
      version = DocsKit::DocVersion.new(id: "1.0")
      DocsKit.configure { |c| c.versions = [version] }

      expect(DocsKit.configuration.versions).to eq([version])
    end

    it "coerces a nil assignment back to an empty array" do
      DocsKit.configure { |c| c.versions = nil }

      expect(DocsKit.configuration.versions).to eq([])
    end
  end

  describe "#versioning_enabled?" do
    it "is false by default (the backwards-compat pin)" do
      expect(described_class.new.versioning_enabled?).to be(false)
    end

    it "is false with a single configured version (no switcher for one entry)" do
      DocsKit.configure { |c| c.versions = [{ id: "1.0", current: true }] }

      expect(DocsKit.configuration.versioning_enabled?).to be(false)
    end

    it "is true with two or more versions" do
      DocsKit.configure { |c| c.versions = [{ id: "1.1", current: true }, { id: "1.0" }] }

      expect(DocsKit.configuration.versioning_enabled?).to be(true)
    end
  end

  describe "#current_version" do
    it "is nil when no versions are configured" do
      expect(described_class.new.current_version).to be_nil
    end

    it "is the entry marked current: true" do
      DocsKit.configure { |c| c.versions = [{ id: "1.0" }, { id: "1.1", current: true }] }

      expect(DocsKit.configuration.current_version.id).to eq("1.1")
    end

    it "falls back to the first entry when none is marked current" do
      DocsKit.configure { |c| c.versions = [{ id: "1.1" }, { id: "1.0" }] }

      expect(DocsKit.configuration.current_version.id).to eq("1.1")
    end
  end

  describe "#version" do
    it "looks an entry up by id" do
      DocsKit.configure { |c| c.versions = [{ id: "1.1", current: true }, { id: "1.0" }] }

      expect(DocsKit.configuration.version("1.0").id).to eq("1.0")
    end

    it "is nil for an unknown id" do
      DocsKit.configure { |c| c.versions = [{ id: "1.1", current: true }] }

      expect(DocsKit.configuration.version("9.9")).to be_nil
    end

    it "is nil for nil (no version param on the request)" do
      DocsKit.configure { |c| c.versions = [{ id: "1.1", current: true }] }

      expect(DocsKit.configuration.version(nil)).to be_nil
    end
  end

  describe "#resolve_version" do
    it "resolves a known id" do
      DocsKit.configure { |c| c.versions = [{ id: "1.1", current: true }, { id: "1.0" }] }

      expect(DocsKit.configuration.resolve_version("1.0").id).to eq("1.0")
    end

    it "falls back to the current version for an unknown or missing id" do
      DocsKit.configure { |c| c.versions = [{ id: "1.1", current: true }, { id: "1.0" }] }

      expect(DocsKit.configuration.resolve_version("9.9").id).to eq("1.1")
      expect(DocsKit.configuration.resolve_version(nil).id).to eq("1.1")
    end

    it "is nil on an unversioned site" do
      expect(described_class.new.resolve_version(nil)).to be_nil
    end
  end

  describe "#nav_groups under a version scope" do
    let(:fixtures_root) { File.expand_path("../fixtures/snapshots", __dir__) }
    let(:live_registry) do
      Class.new do
        def self.nav_items
          { "Guide" => [DocsKit::NavItem.new(href: "/docs/live", label: "Live")] }
        end
      end
    end

    before do
      DocsKit::Snapshot.reset_cache!
      DocsKit.configure do |c|
        c.snapshots_path = fixtures_root
        c.versions = [{ id: "1.1", current: true }, { id: "1.0" }]
        c.nav_registries = { "Live docs" => live_registry }
      end
    end

    it "derives the sidebar from the snapshot for an archived version in scope" do
      DocsKit::Scope.with(version: DocsKit.configuration.version("1.0")) do
        groups = DocsKit.configuration.nav_groups

        expect(groups.keys).to eq(["Docs"])
        expect(groups["Docs"]["Getting started"].map(&:href))
          .to all(start_with("/1.0/docs/"))
      end
    end

    it "behaves exactly as today for the current version in scope" do
      DocsKit::Scope.with(version: DocsKit.configuration.version("1.1")) do
        expect(DocsKit.configuration.nav_groups.keys).to eq(["Live docs"])
      end
    end

    it "behaves exactly as today with no scope (the backwards-compat pin)" do
      expect(DocsKit.configuration.nav_groups.keys).to eq(["Live docs"])
    end
  end

  describe "#repo_url" do
    it "defaults to nil" do
      expect(described_class.new.repo_url).to be_nil
    end
  end

  describe "#snapshots_path" do
    it "defaults to nil outside Rails (no Rails.root to resolve against)" do
      expect(described_class.new.snapshots_path).to be_nil
    end

    it "returns the configured path verbatim" do
      DocsKit.configure { |c| c.snapshots_path = "/srv/app/docs_snapshots" }

      expect(DocsKit.configuration.snapshots_path).to eq("/srv/app/docs_snapshots")
    end
  end

  describe "#compare_url" do
    let(:from) { DocsKit::DocVersion.new(id: "1.0", ref: "v1.0.0") }
    let(:to) { DocsKit::DocVersion.new(id: "1.1", ref: "v1.1.0", current: true) }

    it "builds a GitHub compare URL from repo_url and the two refs" do
      DocsKit.configure { |c| c.repo_url = "https://github.com/me/repo/" }

      expect(DocsKit.configuration.compare_url(from, to))
        .to eq("https://github.com/me/repo/compare/v1.0.0...v1.1.0")
    end

    it "is nil without repo_url" do
      expect(described_class.new.compare_url(from, to)).to be_nil
    end

    it "is nil when either side has no ref" do
      DocsKit.configure { |c| c.repo_url = "https://github.com/me/repo" }
      refless = DocsKit::DocVersion.new(id: "0.9")

      expect(DocsKit.configuration.compare_url(refless, to)).to be_nil
      expect(DocsKit.configuration.compare_url(from, refless)).to be_nil
    end
  end
end
