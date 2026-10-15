# frozen_string_literal: true

require_relative "../support/ractor_canary"

# docs-kit's Ractor canary (Ruby 4.0; skipped with a reason below): the parts of
# a docs site that are plain Ruby over literal data must run inside a non-main
# Ractor and return what they return on the main one. Rendering cannot yet: the
# pending groups document why, and turn red (an unexpected pass) the day an
# upstream fix lands, so the canary can grow.
RSpec.describe "docs-kit inside a non-main Ractor" do # rubocop:disable RSpec/DescribeClass
  describe "DocsKit::SearchIndex, built from literal pages" do
    let(:subject_call) do
      lambda do |pages, query|
        DocsKit::SearchIndex.new(pages).search(query).map { |hit| [hit.href, hit.score, hit.snippet.to_s] }
      end
    end

    it_behaves_like "runs inside a non-main Ractor", inputs: [DocsKitRactorCanary::PAGES, "theme"]
  end

  describe "DocsKit::LlmsText, assembled from a literal registry" do
    let(:subject_call) do
      lambda do |registry, pages|
        config = DocsKit::Configuration.new
        config.brand = "Canary"
        config.tagline = "Docs for the canary."
        config.mcp = false
        config.nav_registries = { "Docs" => registry }
        [DocsKit::LlmsText.index(config, base_url: "https://docs.example"),
         DocsKit::LlmsText.full(config, pages.map { |title, _href, markdown| [title, markdown] })]
      end
    end

    it_behaves_like "runs inside a non-main Ractor", inputs: [DocsKitRactorCanary::Docs, DocsKitRactorCanary::PAGES]
  end

  describe "DocsKit::Registry#nav_items, the sidebar tree of a literal registry" do
    let(:subject_call) { lambda(&:nav_items) }

    it_behaves_like "runs inside a non-main Ractor", inputs: [DocsKitRactorCanary::Docs]
  end

  context "when rendering a DocsUI component (Phlex)",
          pending: "Phlex rendering inside a Ractor is pending upstream (yippee-fun/phlex#1055)" do
    let(:subject_call) { -> { DocsUI::Callout.new(:tip, title: "Tip").call } }

    it_behaves_like "runs inside a non-main Ractor"
  end

  context "when rendering Markdown to HTML (DocsUI::Markdown, commonmarker)",
          pending: "commonmarker defines its options with un-shareable Procs (a RuntimeError in a " \
                   "non-main Ractor), and Phlex rendering inside a Ractor is pending upstream " \
                   "(yippee-fun/phlex#1055)" do
    let(:subject_call) { ->(source) { DocsUI::Markdown.new(source).call } }

    it_behaves_like "runs inside a non-main Ractor", inputs: ["## Add the gem\n\nRun `bundle add docs-kit`.\n"]
  end

  context "when exporting a page's Markdown twin (DocsKit::MarkdownExport, Nokogiri)",
          pending: "nokogiri's C extension is not Ractor-safe (Ractor::UnsafeError), and Phlex " \
                   "rendering inside a Ractor is pending upstream (yippee-fun/phlex#1055)" do
    let(:subject_call) { -> { DocsKit::MarkdownExport.new(DocsKitRactorCanary::Page.new).to_md } }

    it_behaves_like "runs inside a non-main Ractor"
  end
end
