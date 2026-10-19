# frozen_string_literal: true

require "rails"
require "importmap-rails"
require "docs_kit/engine"

# The gem's config/importmap.rb drawn into a real Importmap::Map, the way
# importmap-rails draws it into a host's map (no Rails boot). The host's
# config.docs_kit.preload and config.docs_kit.controllers_under shape the pin;
# the asset it points at never changes.
RSpec.describe "The engine's import map pin" do # rubocop:disable RSpec/DescribeClass
  let(:options) { DocsKit::Engine.config.docs_kit }
  let(:asset) { "docs_kit/controllers/docs_nav_controller.js" }
  # Stands in for a host's asset helpers: a pin resolves to its logical path.
  let(:resolver) { Class.new { def path_to_asset(path) = path }.new }

  # config.docs_kit is the process-wide engine config a host's application.rb
  # sets, so restore it after every example: a changed option must not leak.
  around do |example|
    saved = options.dup
    example.run
  ensure
    options.replace(saved)
  end

  def draw = Importmap::Map.new.draw(DocsKit::Engine.root.join("config/importmap.rb"))
  def imports(map) = JSON.parse(map.to_json(resolver:)).fetch("imports")

  # Keyed by entry point, as javascript_importmap_module_preload_tags keys it:
  # the map caches preloads per cache_key, not per entry point.
  def preloads(map, entry_point: "application")
    map.preloaded_module_paths(resolver:, entry_point:, cache_key: entry_point)
  end

  it "pins docs-nav as docs_kit/controllers/docs_nav_controller by default" do
    expect(imports(draw)).to eq("docs_kit/controllers/docs_nav_controller" => asset)
  end

  it "does not preload docs-nav by default, so no page downloads it unasked" do
    expect(preloads(draw)).not_to include(asset)
  end

  it "preloads docs-nav for every entry point when preload is true" do
    options.preload = true
    map = draw

    expect(preloads(map)).to include(asset)
    expect(preloads(map, entry_point: "docs")).to include(asset)
  end

  it "preloads docs-nav only for the named entry point when preload is an entry point" do
    options.preload = "docs"
    map = draw

    expect(preloads(map, entry_point: "docs")).to include(asset)
    expect(preloads(map)).not_to include(asset)
  end

  it "pins docs-nav under the host's own namespace when controllers_under is set, at the same asset" do
    options.controllers_under = "controllers"

    expect(imports(draw)).to eq("controllers/docs_nav_controller" => asset)
  end
end
