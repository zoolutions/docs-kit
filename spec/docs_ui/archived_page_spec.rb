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

  let(:entry) do
    Struct.new(:title, :markdown).new("Installation", "Add the **gem** first.")
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
end
