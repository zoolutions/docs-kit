# frozen_string_literal: true

RSpec.describe DocsKit::Registry do
  # A representative site registry built on the mixin.
  let(:registry) do
    Class.new do
      extend DocsKit::Registry

      entries [
        { slug: "installation", title: "Installation", group: "Guide", view: "Installation" },
        { slug: "security",     title: "Security",     group: "Guide", view: "Missing" },
        { slug: "counter",      title: "Counter",      group: "Examples", view: "Counter" }
      ]

      attr_reader :slug, :title, :group, :view_name

      def initialize(entry)
        @slug = entry[:slug]
        @title = entry[:title]
        @group = entry[:group]
        @view_name = entry[:view]
      end

      # Stand-in for safe_constantize: only "Installation"/"Counter" are "authored".
      def view_class
        %w[Installation Counter].include?(view_name) ? Object : nil
      end
    end
  end

  it "builds all instances from entries" do
    expect(registry.all.map(&:slug)).to eq(%w[installation security counter])
  end

  it "looks up by slug, nil when missing" do
    expect(registry.from_slug("counter").title).to eq("Counter")
    expect(registry.from_slug("nope")).to be_nil
  end

  it "groups by the group attribute, preserving order" do
    grouped = registry.grouped
    expect(grouped.keys).to eq(%w[Guide Examples])
    expect(grouped["Guide"].map(&:slug)).to eq(%w[installation security])
  end

  it "supports the 'authored' filter (only entries with a resolvable view)" do
    authored = registry.all.select(&:view_class).group_by(&:group)
    expect(authored["Guide"].map(&:slug)).to eq(%w[installation])
    expect(authored["Examples"].map(&:slug)).to eq(%w[counter])
  end

  it "freezes the entries so a site cannot mutate the registry" do
    expect(registry.entries).to be_frozen
    expect(registry.entries.first).to be_frozen
  end

  it "allows a custom grouping attribute" do
    klass = Class.new do
      extend DocsKit::Registry

      entries [{ slug: "a", category: "Actions" }]
      group_by_attribute :category
      attr_reader :slug, :category

      def initialize(entry)
        @slug = entry[:slug]
        @category = entry[:category]
      end
    end

    expect(klass.grouped.keys).to eq(%w[Actions])
  end

  it "builds nav_items honoring a custom group_by_attribute (no #view_class/#group required)" do
    klass = Class.new do
      extend DocsKit::Registry

      entries [{ slug: "a", category: "Actions" }]
      group_by_attribute :category
      attr_reader :slug, :category

      def initialize(entry)
        @slug = entry[:slug]
        @category = entry[:category]
      end
    end

    expect(klass.nav_items).to eq({})
  end

  # ---------------------------------------------------------------------------
  # Registry v2: the one-line `page` DSL. A site declares pages with a single
  # line; slug/view derive from the title (both overridable), instances get the
  # default readers + view_class + href for free, and the sidebar nav derives
  # from the registry with zero site code.
  # ---------------------------------------------------------------------------
  describe "the page DSL (v2)" do
    let(:v2) do
      Class.new do
        extend DocsKit::Registry

        path_prefix "/docs"
        view_namespace "DocsKit"

        page "Installation", group: "Guide"
        page "Getting started", group: "Guide", icon: "rocket"
        page "OAuth", group: "Guide", slug: "auth", view: "String"
      end
    end

    it "derives slug (parameterize) and view (camelize) from the title" do
      getting_started = v2.from_slug("getting-started")
      expect(getting_started.slug).to eq("getting-started")
      expect(getting_started.view_name).to eq("GettingStarted")
      expect(getting_started.title).to eq("Getting started")
      expect(getting_started.group).to eq("Guide")
    end

    it "lets slug and view overrides win over the derived values" do
      oauth = v2.from_slug("auth")
      expect(oauth.slug).to eq("auth")
      expect(oauth.view_name).to eq("String")
    end

    it "exposes all/grouped over page-declared entries, preserving order" do
      expect(v2.all.map(&:slug)).to eq(%w[installation getting-started auth])
      expect(v2.grouped.keys).to eq(%w[Guide])
      expect(v2.grouped["Guide"].map(&:slug)).to eq(%w[installation getting-started auth])
    end

    it "resolves view_class under view_namespace via safe_constantize (nil until authored)" do
      # "DocsKit::String" does not exist → unauthored; "DocsKit::Installation" ditto.
      expect(v2.from_slug("installation").view_class).to be_nil
      # A registry whose view resolves under the namespace is 'authored'.
      authored = Class.new do
        extend DocsKit::Registry

        view_namespace "DocsKit"
        page "Configuration", group: "Guide" # → DocsKit::Configuration (exists)
      end
      expect(authored.from_slug("configuration").view_class).to eq(DocsKit::Configuration)
    end

    it "builds an href from path_prefix and slug" do
      expect(v2.from_slug("getting-started").href).to eq("/docs/getting-started")
    end

    it "treats every page as unauthored when view_namespace is unset" do
      no_ns = Class.new do
        extend DocsKit::Registry

        page "Configuration", group: "Guide" # DocsKit::Configuration exists, but no namespace
      end
      expect(no_ns.from_slug("configuration").view_class).to be_nil
      expect(no_ns.nav_items).to eq({})
    end

    it "carries the optional icon through to the instance" do
      expect(v2.from_slug("getting-started").icon).to eq("rocket")
      expect(v2.from_slug("installation").icon).to be_nil
    end

    describe ".nav_items" do
      # Only authored pages (a resolvable view_class) become NavItems, so the
      # sidebar never links a page that isn't written yet.
      let(:registry) do
        Class.new do
          extend DocsKit::Registry

          path_prefix "/docs"
          view_namespace "DocsKit"

          page "Configuration", group: "Guide", icon: "gear"     # DocsKit::Configuration exists
          page "Registry",      group: "Guide"                   # DocsKit::Registry exists
          page "Nonexistent",   group: "Reference"               # unauthored → dropped
        end
      end

      it "returns { group => [NavItem] } for authored pages only" do
        nav = registry.nav_items
        expect(nav.keys).to eq(%w[Guide])
        expect(nav["Guide"].map(&:label)).to eq(%w[Configuration Registry])
      end

      it "builds NavItems with the derived href and the declared icon" do
        item = registry.nav_items["Guide"].first
        expect(item).to be_a(DocsKit::NavItem)
        expect(item.href).to eq("/docs/configuration")
        expect(item.icon).to eq("gear")
      end
    end

    it "path_prefix defaults to /docs when unset" do
      klass = Class.new do
        extend DocsKit::Registry

        view_namespace "DocsKit"
        page "Configuration", group: "Guide"
      end
      expect(klass.from_slug("configuration").href).to eq("/docs/configuration")
    end

    it "raises when `page` follows `entries` in one registry" do
      expect do
        Class.new do
          extend DocsKit::Registry

          entries [{ slug: "a", title: "A", group: "G", view: "A" }]
          page "B", group: "G"
        end
      end.to raise_error(DocsKit::Registry::Error, /cannot mix/i)
    end

    it "raises when `entries` follows `page` in one registry" do
      expect do
        Class.new do
          extend DocsKit::Registry

          page "B", group: "G"
          entries [{ slug: "a", title: "A", group: "G", view: "A" }]
        end
      end.to raise_error(DocsKit::Registry::Error, /cannot mix/i)
    end
  end

  describe "Entry#renderable" do
    it "instantiates the authored view class (the seam snapshot entries share)" do
      authored = Class.new do
        extend DocsKit::Registry

        view_namespace "DocsKit"
        page "Configuration", group: "Guide" # → DocsKit::Configuration (exists)
      end

      expect(authored.from_slug("configuration").renderable).to be_a(DocsKit::Configuration)
    end

    it "is nil for an unauthored page (no resolvable view_class)" do
      unwritten = Class.new do
        extend DocsKit::Registry

        view_namespace "DocsKit"
        page "Installation", group: "Guide" # DocsKit::Installation does not exist
      end

      expect(unwritten.from_slug("installation").renderable).to be_nil
    end
  end
end
