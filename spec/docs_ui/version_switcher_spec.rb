# frozen_string_literal: true

RSpec.describe DocsUI::VersionSwitcher do
  let(:fixtures_root) { File.expand_path("../fixtures/snapshots", __dir__) }

  # A live registry with an authored "installation" page (the slug the 1.0
  # fixture snapshot also has) plus a live-only page absent from the snapshot.
  let(:live_registry) do
    entry = Struct.new(:title, :href, :slug, :group, :icon, :view_class, keyword_init: true)
    pages = [
      entry.new(title: "Installation", href: "/docs/installation", slug: "installation",
                group: "Guide", icon: nil, view_class: Class.new),
      entry.new(title: "Live only", href: "/docs/live-only", slug: "live-only",
                group: "Guide", icon: nil, view_class: Class.new)
    ]
    Class.new do
      define_singleton_method(:all) { pages }
      define_singleton_method(:nav_items) { {} }
    end
  end

  def configure_versions
    DocsKit.configure do |c|
      c.versions = [{ id: "1.1", current: true }, { id: "1.0" }]
      c.snapshots_path = fixtures_root
      c.nav_registries = { "Docs" => live_registry }
    end
  end

  # The switcher reads the request path through the guarded #current_path seam
  # (like DocsUI::Sidebar); pin it per example instead of faking a Rails request.
  def switcher(path: nil)
    Class.new(described_class) do
      define_method(:current_path) { path }
    end.new
  end

  before { DocsKit::Snapshot.reset_cache! }

  it "renders NOTHING when versioning is not enabled (the byte-identical-topbar pin)" do
    expect(switcher(path: "/docs/installation").call).to eq("")
  end

  it "renders one link per configured version" do
    configure_versions

    html = switcher(path: "/docs/installation").call

    expect(html).to include('href="/docs/installation"')
    expect(html).to include('href="/1.0/docs/installation"')
  end

  it "keeps the same slug when moving from an archived version back to current" do
    configure_versions

    html = nil
    DocsKit::Scope.with(version: DocsKit.configuration.version("1.0")) do
      html = switcher(path: "/1.0/docs/installation").call
    end

    expect(html).to include('href="/docs/installation"')
    expect(html).to include('href="/1.0/docs/installation"')
  end

  it "marks the in-scope version" do
    configure_versions

    html = nil
    DocsKit::Scope.with(version: DocsKit.configuration.version("1.0")) do
      html = switcher(path: "/1.0/docs/installation").call
    end

    expect(html).to include('aria-current="true"')
    expect(html).to match(/aria-current="true"[^>]*>(\s*)1\.0/m)
  end

  it "shows the in-scope version's label on the trigger" do
    configure_versions

    DocsKit::Scope.with(version: DocsKit.configuration.version("1.0")) do
      expect(switcher(path: "/1.0/docs/installation").call).to include("1.0")
    end
  end

  it "falls back to the target version's first page when the slug is absent there" do
    configure_versions

    # /docs/live-only has no 1.0 twin → the 1.0 link goes to 1.0's first page,
    # never a 404.
    html = switcher(path: "/docs/live-only").call

    expect(html).to include('href="/1.0/docs/installation"')
    expect(html).not_to include('href="/1.0/docs/live-only"')
  end

  it "works without a request path (isolated render — links fall back, no raise)" do
    configure_versions

    expect { switcher.call }.not_to raise_error
  end

  it "is a CSS-only daisyUI dropdown (no Stimulus controller, works with JS off)" do
    configure_versions

    html = switcher(path: "/docs/installation").call

    expect(html).to include("dropdown")
    expect(html).not_to include("data-controller")
  end
end
