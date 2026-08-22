# frozen_string_literal: true

# The full document wraps in DocsUI::Shell, whose <head> needs a live Rails view
# context (csrf_meta_tags etc.) — so, like the Shell specs, exercise the page
# BODY through a subclass that renders only #body. The banner + full-page specs
# land with the version switcher (issue #61 phase 4).
RSpec.describe DocsUI::ArchivedPage do
  let(:body_only) do
    Class.new(described_class) do
      def view_template = body
    end
  end

  let(:archived_version) { DocsKit::DocVersion.new(id: "1.0") }

  let(:entry) do
    entry_struct.new(title: "Installation", markdown: "Add the **gem** first.",
                     slug: "installation", version: archived_version)
  end

  def entry_struct
    Struct.new(:title, :markdown, :slug, :version, keyword_init: true)
  end

  # A live registry authoring the same slug, so the banner can link the
  # current-version equivalent.
  def live_registry
    page_struct = Struct.new(:title, :href, :slug, :group, :icon, :view_class, keyword_init: true)
    page = page_struct.new(title: "Installation", href: "/docs/installation", slug: "installation",
                           group: "Guide", icon: nil, view_class: Class.new)
    Class.new do
      define_singleton_method(:all) { [page] }
      define_singleton_method(:nav_items) { {} }
    end
  end

  def configure_versions
    registry = live_registry
    DocsKit.configure do |c|
      c.versions = [{ id: "1.1", current: true }, { id: "1.0" }]
      c.nav_registries = { "Docs" => registry }
    end
  end

  it "renders the entry's Markdown body through the chrome's Markdown island" do
    html = body_only.new(entry: entry).call

    expect(html).to include("<strong>gem</strong>")
  end

  it "renders the entry title as the masthead" do
    html = body_only.new(entry: entry).call

    expect(html).to include("Installation")
    expect(html).to include("<h1")
  end

  it "renders an empty body with no entry (naive view_class.new never raises)" do
    # The Shell wrapper needs a Rails view context in every case (csrf_meta_tags),
    # so "never raises" is proven at the two seams a bare render exercises:
    # all-defaulted construction, and an empty body.
    expect(described_class.new).to be_a(described_class)
    expect(body_only.new.call).to eq("")
  end

  describe "the archived banner" do
    it "names both versions and links the current-version equivalent" do
      configure_versions

      html = body_only.new(entry: entry).call

      expect(html).to include("You are viewing the 1.0 docs")
      expect(html).to include("The current version is 1.1")
      expect(html).to include('href="/docs/installation"')
    end

    it "falls back to the docs home when the slug has no current equivalent" do
      configure_versions
      gone = entry_struct.new(title: "Removed", markdown: "Old.", slug: "removed",
                              version: archived_version)

      html = body_only.new(entry: gone).call

      expect(html).to include("You are viewing the 1.0 docs")
      expect(html).to include(%(href="#{DocsKit.configuration.brand_href}"))
    end

    it "is absent for a current-version entry" do
      configure_versions
      current = entry_struct.new(title: "Installation", markdown: "New.", slug: "installation",
                                 version: DocsKit::DocVersion.new(id: "1.1", current: true))

      expect(body_only.new(entry: current).call).not_to include("You are viewing")
    end

    it "is absent for an entry that carries no version (a bare stub)" do
      versionless = Struct.new(:title, :markdown).new("Installation", "Body.")

      expect(body_only.new(entry: versionless).call).not_to include("You are viewing")
    end

    it "carries data-md-skip so it never leaks into the .md twin" do
      configure_versions

      html = body_only.new(entry: entry).call

      expect(html).to match(/data-md-skip[^>]*>.*You are viewing/m)
    end
  end
end
