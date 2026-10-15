# frozen_string_literal: true

require "open3"

# DocsUI::Page's `on_page` class-level accessor is the per-page auto-TOC knob.
# Page cannot autoload in the Rails-free suite (it includes
# Phlex::Rails::Helpers::Routes, whose body runs Rails.* at class-load time — see
# the "page-not-loadable-in-suite" note and spec/docs_ui/page_helpers_spec.rb).
# A global Rails stub would break icon_spec/the generator spec under random
# ordering, so exercise the REAL DocsUI::Page.on_page in an isolated child
# process (a minimal Rails routes stub lets Page load there without polluting the
# suite) and assert the contract: an unset on_page resolves to
# DocsKit.configuration.on_page_default, never a bare `true`.
# The subject is DocsUI::Page, but describing it by name (not the constant) is
# deliberate — referencing the constant would autoload Page and break the suite.
RSpec.describe "DocsUI::Page.on_page" do # rubocop:disable RSpec/DescribeClass
  gem_root = File.expand_path("../..", __dir__)

  # Load the real DocsUI::Page in a child process and return the inspected
  # `on_page` of a subclass, after applying `config` (a Configuration block body)
  # and `on_page` (statements against the subclass `klass`).
  define_method(:resolve) do |config: "", on_page: ""|
    script = <<~RUBY
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
      DocsKit.configure { |c| #{config} }
      klass = Class.new(DocsUI::Page)
      #{on_page}
      print klass.on_page.inspect
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", script)
    raise "child process failed: #{stderr}" unless status.success?

    stdout
  end

  context "when no per-page value is set" do
    it "defaults to the configured on_page_default, not a bare true" do
      expect(resolve(config: "c.on_page_default = :panel")).to eq(":panel")
    end
  end

  context "when set to an explicit mode" do
    it "returns that mode" do
      expect(resolve(on_page: "klass.on_page :toggle")).to eq(":toggle")
    end
  end

  context "when opted out with false" do
    it "returns false" do
      expect(resolve(on_page: "klass.on_page false")).to eq("false")
    end
  end

  # The per-page description feeds DocsUI::MetaTags (via Shell). A page CAN set an
  # explicit description; when it doesn't, the value derives from #lead; with
  # neither, it's nil (DocsUI::MetaTags then falls back to config.seo.description).
  # Resolved as `self.class.description || lead` — the exact expression
  # Page#view_template threads into Shell.new(description:). Exercised in the same
  # isolated child process as on_page (Page needs Rails to load).
  define_method(:resolve_description) do |body: ""|
    script = <<~RUBY
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
      klass = Class.new(DocsUI::Page) do
        #{body}
        def content = nil
      end
      instance = klass.allocate
      print (klass.description || instance.lead).inspect
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", script)
    raise "child process failed: #{stderr}" unless status.success?

    stdout
  end

  # The masthead "← Docs home" link follows config.brand_href — the DOCS home —
  # never the host app's root_path helper (on an app-embedded site root_path is
  # the app dashboard, which bounced anonymous readers off the docs; see
  # issue #62). Exercised through #home_href in the same
  # isolated child process (Page needs Rails to load).
  define_method(:resolve_home_href) do |config: ""|
    script = <<~RUBY
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
      DocsKit.configure { |c| #{config} }
      klass = Class.new(DocsUI::Page) { def content = nil }
      print klass.allocate.send(:home_href).inspect
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", script)
    raise "child process failed: #{stderr}" unless status.success?

    stdout
  end

  describe "DocsUI::Page#home_href (the masthead \"← Docs home\" target)" do
    it "defaults to \"/\" — the same destination root_path resolved to on a standalone site" do
      expect(resolve_home_href).to eq('"/"')
    end

    it "follows config.brand_href so an app-embedded site points it at the docs landing" do
      expect(resolve_home_href(config: 'c.brand_href = "/docs"')).to eq('"/docs"')
    end
  end

  describe "DocsUI::Page.description (the per-page SEO description)" do
    it "returns an explicitly set description" do
      expect(resolve_description(body: %(description "Add the gem and render."))).to eq('"Add the gem and render."')
    end

    it "falls back to #lead when no description is set" do
      expect(resolve_description(body: "def lead = \"A lead paragraph.\"")).to eq('"A lead paragraph."')
    end

    it "is nil when neither a description nor a lead is set" do
      expect(resolve_description).to eq("nil")
    end

    it "prefers an explicit description over #lead" do
      body = %(description "Explicit."\ndef lead = "Derived.")
      expect(resolve_description(body: body)).to eq('"Explicit."')
    end
  end

  # The class macros run in a page's class body at load and make each value
  # shareable on write, so request threads (and a non-main Ractor) only ever
  # read frozen values. Same isolated child process (Page needs Rails to load).
  define_method(:macro_values_shareable?) do
    script = <<~RUBY
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
      klass = Class.new(DocsUI::Page)
      klass.title(+"Installation")
      klass.eyebrow(+"Guide")
      klass.description(+"Add the gem.")
      klass.on_page(:toggle)
      print [klass.title, klass.eyebrow, klass.description, klass.on_page].all? { Ractor.shareable?(_1) }
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", script)
    raise "child process failed: #{stderr}" unless status.success?

    stdout
  end

  it "makes every class macro value Ractor-shareable on write" do
    expect(macro_values_shareable?).to eq("true")
  end
end
