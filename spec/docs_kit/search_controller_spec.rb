# frozen_string_literal: true

# Like DocsKit::LlmsController, DocsKit::SearchController subclasses
# ActionController::Base, so it can't load in the standalone suite (no Rails
# request stack). Its index-building + scoring is covered by
# spec/docs_kit/search_index_spec.rb and its results markup by
# spec/docs_ui/search_results_spec.rb; here we prove the SHIPPED FILE is where
# Rails autoloads DocsKit::SearchController from, and that it wires the index +
# the html/json seams the way the JS-off form and the palette need. The
# end-to-end request behavior is dogfooded against the docs/ app (see the PR).
# rubocop:disable-next RSpec/DescribeClass -- the class is Rails-only, can't constantize here
RSpec.describe "DocsKit::SearchController (source wiring)" do
  let(:path) do
    File.expand_path("../../app/controllers/docs_kit/search_controller.rb", __dir__)
  end
  let(:source) { File.read(path) }

  it "ships at the path Rails autoloads DocsKit::SearchController from" do
    expect(File.exist?(path)).to be(true)
  end

  it "declares DocsKit::SearchController < ActionController::Base" do
    expect(source).to include("module DocsKit")
    expect(source).to include("class SearchController < ActionController::Base")
  end

  it "exposes the #index action" do
    expect(source).to match(/def index\b/)
  end

  it "declares protect_from_forgery (the Shell's <head> calls csrf_meta_tags)" do
    # A bare ActionController::Base subclass doesn't inherit the host's forgery
    # default, and #index renders the Shell whose <head> emits csrf_meta_tags.
    expect(source).to include("protect_from_forgery")
  end

  it "does not shadow ActionController::Base#config (forgery delegates to it)" do
    # Same guard as LlmsController: a `def config` breaks csrf_meta_tags when the
    # Shell renders. The DocsKit config reader is #docs_config.
    expect(source).not_to match(/^\s*def config\b/)
    expect(source).to include("DocsKit.configuration")
  end

  it "builds the index from DocsKit::SearchIndex" do
    expect(source).to include("DocsKit::SearchIndex")
  end

  it "renders each registry page's Markdown twin via DocsKit::MarkdownExport" do
    # The index is built from the SAME twins llms-full.txt uses, so search never
    # drifts from the pages.
    expect(source).to include("DocsKit::MarkdownExport")
  end

  it "responds to both html (the JS-off form) and json (the palette)" do
    expect(source).to match(/respond_to\b/)
    expect(source).to match(/\.html\b/)
    expect(source).to match(/\.json\b/)
  end

  it "renders the DocsUI::SearchResults component for the html path" do
    expect(source).to include("DocsUI::SearchResults")
  end

  it "wraps results in DocsUI::Shell (a full chrome page, layout: false)" do
    expect(source).to include("DocsUI::Shell")
    expect(source).to include("layout: false")
  end

  it "wraps every action in the request's version scope (DocsKit::Scoping)" do
    expect(source).to include("include DocsKit::Scoping")
  end
end
