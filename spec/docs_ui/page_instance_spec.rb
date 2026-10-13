# frozen_string_literal: true

require "open3"

# DocsUI::Page reads its title, description and eyebrow through INSTANCE readers
# that default to the class macros, so one page class can render many records
# (one reference page per item) with a title each — no anonymous subclass per
# render (issue #95). The class macros inherit from a parent page when unset.
#
# Page cannot autoload in the Rails-free suite (see spec/docs_ui/page_spec.rb),
# so each example renders the REAL page in a child process: a minimal Rails
# routes stub lets Page load, and the Shell's view-context-only head helpers
# (csrf/csp/stylesheet/importmap tags) are no-ops. Everything else — <title>,
# the meta description, the masthead <h1> and eyebrow — is the real markup.
RSpec.describe "DocsUI::Page instance title/description/eyebrow" do # rubocop:disable RSpec/DescribeClass
  gem_root = File.expand_path("../..", __dir__)

  # Loads the real DocsUI::Page and defines `base`, a renderable page subclass.
  preamble = <<~RUBY
    $LOAD_PATH.unshift "#{gem_root}/lib"
    require "active_support/all"
    require "action_dispatch"
    require "phlex/rails"
    require "daisy_ui"
    module Rails
      def self.application
        @app ||= Class.new do
          def routes = @routes ||= ActionDispatch::Routing::RouteSet.new
        end.new
      end
    end
    require "docs_kit"
    DocsUI::Shell.prepend(Module.new do
      %i[csrf_meta_tags csp_meta_tag javascript_importmap_tags].each { |m| define_method(m) { |*| nil } }
      define_method(:stylesheet_link_tag) { |*, **| nil }
    end)
    base = Class.new(DocsUI::Page) do
      def request = Struct.new(:path).new("/docs/widget")
      def content = p { "Body" }
    end
  RUBY

  # Render the page class built by `body` (statements defining `klass`, a
  # DocsUI::Page subclass of `base`) and return the HTML.
  define_method(:render_page) do |body|
    script = "#{preamble}\n#{body}\nprint klass.new.call\n"
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", script)
    raise "child process failed: #{stderr}" unless status.success?

    stdout
  end

  def h1_text(html) = html[%r{<h1[^>]*>(.*?)</h1>}, 1]
  def head_title(html) = html[%r{<title>(.*?)</title>}, 1]
  def meta_description(html) = html[/<meta name="description" content="([^"]*)"/, 1]

  context "when the instance defines #title (no class-level title)" do
    let(:html) { render_page('klass = Class.new(base) { def title = "Gadget" }') }

    it "renders it as the masthead <h1>" do
      expect(h1_text(html)).to eq("Gadget")
    end

    it "renders it in the document <title>" do
      expect(head_title(html)).to eq("Gadget · Docs")
    end
  end

  context "when the instance defines #description" do
    let(:html) do
      render_page(<<~RUBY)
        klass = Class.new(base) do
          title "Widget"
          description "Class-level."
          def lead = "The lead."
          def description = "Per record."
        end
      RUBY
    end

    it "overrides the class macro and the lead in the meta description" do
      expect(meta_description(html)).to eq("Per record.")
    end
  end

  context "when the instance defines #eyebrow" do
    let(:html) do
      render_page(%(klass = Class.new(base) { title "Widget"; eyebrow "Class"; def eyebrow = "Instance" }))
    end

    it "renders it above the <h1>" do
      expect(html).to include(">Instance</div>")
      expect(html).not_to include(">Class</div>")
    end
  end

  context "with only class macros" do
    let(:html) do
      render_page(<<~RUBY)
        klass = Class.new(base) do
          title "Widget"
          eyebrow "Widgets"
          description "Class-level."
        end
      RUBY
    end

    it "renders the class title, eyebrow and description" do
      expect(h1_text(html)).to eq("Widget")
      expect(head_title(html)).to eq("Widget · Docs")
      expect(html).to include(">Widgets</div>")
      expect(meta_description(html)).to eq("Class-level.")
    end
  end

  context "with a subclass that sets no eyebrow, description or on_page" do
    let(:html) do
      render_page(<<~RUBY)
        parent = Class.new(base) do
          eyebrow "Widgets"
          description "Parent description."
          on_page :toggle
        end
        klass = Class.new(parent) { def title = "Gadget" }
      RUBY
    end

    it "shows the parent's eyebrow" do
      expect(html).to include(">Widgets</div>")
    end

    it "uses the parent's description" do
      expect(meta_description(html)).to eq("Parent description.")
    end

    it "uses the parent's on_page placement" do
      expect(html).to include('data-docs-nav-on-page-value="toggle"')
    end
  end

  context "with a subclass that sets its own eyebrow" do
    let(:html) do
      render_page(<<~RUBY)
        parent = Class.new(base) { eyebrow "Widgets" }
        klass = Class.new(parent) { title "Gadget"; eyebrow "Gadgets" }
      RUBY
    end

    it "prefers its own eyebrow" do
      expect(html).to include(">Gadgets</div>")
      expect(html).not_to include(">Widgets</div>")
    end
  end
end
