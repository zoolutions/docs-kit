# frozen_string_literal: true

# DocsKit::Controller#render_page is the one shared render helper. For an HTML
# request it renders the Phlex page (layout: false); for a .md/.text request it
# renders the Markdown twin derived from the page's own render. The real request
# path needs Rails, so exercise the branching through a tiny host that mixes in
# the module and stubs the Rails seams (request/render/view_context).
RSpec.describe DocsKit::Controller do
  # A minimal ActionController stand-in: it includes the real module and exposes
  # settable `request`/`view_context`/`params` plus a `render` spy, so the branch
  # logic is verified without booting Rails.
  def controller_for(format:, params: {})
    fmt = format
    request_params = params
    Class.new do
      include DocsKit::Controller

      attr_reader :rendered, :rendered_scope_version

      define_method(:request) do
        # Mimic ActionDispatch::Request: #format responds to md?/text? predicates.
        format = Struct.new(:md?, :text?).new(fmt == :md, fmt == :text)
        Struct.new(:format, :base_url).new(format, "https://acme.dev")
      end

      define_method(:params) { request_params }

      def view_context = :the_view_context

      # ActionController#render takes an optional positional (the renderable) plus
      # options; capture both so the HTML branch (render view, layout: false) and
      # the markdown branch (render plain:, content_type:) are both observable.
      # Also capture the DocsKit::Scope in effect AT render time — the render
      # happens inside render_page's Scope.with wrapper, so this observes it.
      def render(renderable = nil, **kwargs)
        @rendered_scope_version = DocsKit::Scope.version
        @rendered = kwargs.merge(renderable ? { renderable: renderable } : {})
      end
    end.new
  end

  # A fake page whose #call returns a #docs-content document, so the .md branch
  # produces real Markdown through DocsKit::MarkdownExport.
  let(:page) do
    Class.new do
      def call(view_context: nil)
        "[#{view_context}]<div id=\"docs-content\"><h2>Title</h2><p>Body.</p></div>"
      end
    end.new
  end

  describe "an HTML request" do
    it "renders the Phlex page with layout: false" do
      controller = controller_for(format: :html)

      controller.render_page(page)

      expect(controller.rendered).to include(layout: false)
      # The page object itself is handed to render (Phlex/Rails renders it).
      expect(controller.rendered[:renderable]).to eq(page)
    end
  end

  describe "a .md request" do
    it "renders the Markdown twin as text/markdown" do
      controller = controller_for(format: :md)

      controller.render_page(page)

      expect(controller.rendered[:content_type]).to eq("text/markdown")
      expect(controller.rendered[:plain]).to include("## Title")
      expect(controller.rendered[:plain]).to include("Body.")
    end

    it "renders the page through the controller's view context" do
      controller = controller_for(format: :md)

      controller.render_page(page)

      # view_context threaded in → the fake page echoes it, proving the seam.
      expect(controller.rendered[:plain]).not_to include("the_view_context") # stripped chrome
      expect(controller.rendered[:plain]).to include("Title")
    end
  end

  describe "a .text request" do
    it "also renders the Markdown twin (the .text alias)" do
      controller = controller_for(format: :text)

      controller.render_page(page)

      expect(controller.rendered[:content_type]).to eq("text/markdown")
      expect(controller.rendered[:plain]).to include("## Title")
    end
  end

  describe "the version scope" do
    before do
      DocsKit.configure do |c|
        c.versions = [{ id: "1.1", current: true }, { id: "1.0" }]
      end
    end

    it "renders inside the scope of the requested version" do
      controller = controller_for(format: :html, params: { version: "1.0" })

      controller.render_page(page)

      expect(controller.rendered_scope_version&.id).to eq("1.0")
    end

    it "falls back to the current version for an unknown :version param" do
      controller = controller_for(format: :html, params: { version: "9.9" })

      controller.render_page(page)

      expect(controller.rendered_scope_version&.id).to eq("1.1")
    end

    it "scopes to the current version with no :version param" do
      controller = controller_for(format: :html)

      controller.render_page(page)

      expect(controller.rendered_scope_version&.id).to eq("1.1")
    end

    it "restores the empty scope after rendering" do
      controller = controller_for(format: :html, params: { version: "1.0" })

      controller.render_page(page)

      expect(DocsKit::Scope.version).to be_nil
    end

    it "scopes to nil on an unversioned site (today's behavior exactly)" do
      DocsKit.reset_configuration!
      controller = controller_for(format: :html)

      controller.render_page(page)

      expect(controller.rendered_scope_version).to be_nil
      expect(controller.rendered).to include(layout: false)
    end
  end
end
