# frozen_string_literal: true

require "rouge"

# DocsKit.finalize! runs once the host has configured the kit (the engine's
# after_initialize): every per-render lookup — the Rouge theme constants, each
# registered page's view class — is resolved once into frozen values, and the
# lazy memos (brand logo, SEO, landing, the mcp probe) are filled at boot, so a
# request never races to fill them. DocsKit.configure re-opens it.
RSpec.describe "DocsKit.finalize!" do # rubocop:disable RSpec/DescribeClass
  let(:pages) { Module.new }
  let(:registry) do
    Class.new do
      extend DocsKit::Registry

      path_prefix "/docs"
      view_namespace "DocsKitFinalizeSpecPages"
      page "Installation", group: "Guide"
      page "Unwritten", group: "Guide"
    end
  end

  before do
    stub_const("DocsKitFinalizeSpecPages", pages)
    stub_const("DocsKitFinalizeSpecPages::Installation", Class.new)
    site_registry = registry
    DocsKit.configure do |c|
      c.code_theme = "Rouge::Themes::Github"
      c.code_theme_dark = "Rouge::Themes::Monokai"
      c.nav_registries = { "Docs" => site_registry }
    end
  end

  it_behaves_like "a boot-finalized configuration",
                  readers: {
                    "DocsKit.configuration.code_theme_class" => -> { DocsKit.configuration.code_theme_class },
                    "DocsKit.configuration.code_theme_dark_class" => -> { DocsKit.configuration.code_theme_dark_class }
                  },
                  finalize: -> { DocsKit.finalize! }

  it "returns the finalized configuration" do
    expect(DocsKit.finalize!).to be(DocsKit.configuration)
  end

  it "resolves the code themes once, not on every read" do
    DocsKit.finalize!
    allow(Object).to receive(:const_get).and_call_original

    expect(DocsKit.configuration.code_theme_class).to eq(Rouge::Themes::Github)
    expect(DocsKit.configuration.code_theme_dark_class).to eq(Rouge::Themes::Monokai)
    expect(Object).not_to have_received(:const_get)
  end

  it "keeps the default-theme fallback for a name that does not resolve" do
    DocsKit.configure { |c| c.code_theme = "Rouge::Themes::Nope" }
    DocsKit.finalize!

    expect(DocsKit.configuration.code_theme_class).to eq(Rouge::Themes::Monokai)
  end

  it "resolves every registered page's view class once" do
    DocsKit.finalize!
    allow(ActiveSupport::Inflector).to receive(:safe_constantize).and_call_original

    expect(registry.from_slug("installation").view_class).to be(DocsKitFinalizeSpecPages::Installation)
    expect(ActiveSupport::Inflector).not_to have_received(:safe_constantize)
  end

  it "still finds a page authored after finalize (an unresolved view is not cached as missing)" do
    DocsKit.finalize!
    stub_const("DocsKitFinalizeSpecPages::Unwritten", Class.new)

    expect(registry.from_slug("unwritten").view_class).to be(DocsKitFinalizeSpecPages::Unwritten)
  end

  it "fills the brand logo memo at boot" do
    DocsKit.configure { |c| c.brand_logo = { svg: "M0 0Z" } }
    DocsKit.finalize!
    allow(DocsKit::BrandLogo).to receive(:from).and_call_original

    expect(DocsKit.configuration.brand_logo.svg).to eq("M0 0Z")
    expect(DocsKit::BrandLogo).not_to have_received(:from)
  end

  it "is re-opened by DocsKit.configure, so a later setting takes effect" do
    DocsKit.finalize!
    DocsKit.configure { |c| c.code_theme = "Rouge::Themes::Base16" }

    expect(DocsKit.configuration.code_theme_class).to eq(Rouge::Themes::Base16)
  end

  it "re-opens the registries too, so a re-configured page view resolves afresh" do
    DocsKit.finalize!
    replacement = Class.new
    DocsKit.configure { |c| c.code_theme = "Rouge::Themes::Github" }
    stub_const("DocsKitFinalizeSpecPages::Installation", replacement)

    expect(registry.from_slug("installation").view_class).to be(replacement)
  end
end
