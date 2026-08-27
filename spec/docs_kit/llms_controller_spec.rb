# frozen_string_literal: true

# The controller subclasses ActionController::Base, so it can't load in the
# standalone suite (no Rails request stack). Its text shaping is covered by
# spec/docs_kit/llms_text_spec.rb; here we prove the SHIPPED FILE is where Rails
# will autoload DocsKit::LlmsController from, and that the thin controller wires
# the builder + the Rails seams the way #full needs. The end-to-end constant
# load + request behavior is dogfooded against the docs/ app (see the PR).
# rubocop:disable-next RSpec/DescribeClass -- the class is Rails-only, can't constantize here
RSpec.describe "DocsKit::LlmsController (source wiring)" do
  # app/controllers/docs_kit/llms_controller.rb → DocsKit::LlmsController under
  # Rails' default inflector (docs_kit → DocsKit, llms_controller → LlmsController).
  # The engine opts app/ out of the gem's zeitwerk loader (the superclass is
  # Rails-only), so Rails' own autoloader owns this constant from this path.
  let(:path) do
    File.expand_path("../../app/controllers/docs_kit/llms_controller.rb", __dir__)
  end
  let(:source) { File.read(path) }

  it "ships at the path Rails autoloads DocsKit::LlmsController from" do
    expect(File.exist?(path)).to be(true)
  end

  it "declares DocsKit::LlmsController < ActionController::Base" do
    expect(source).to include("module DocsKit")
    expect(source).to include("class LlmsController < ActionController::Base")
  end

  it "exposes the two llmstxt actions" do
    expect(source).to match(/def index\b/)
    expect(source).to match(/def full\b/)
  end

  it "renders text/plain; charset=utf-8 (llms.txt is plain text, not markdown)" do
    expect(source).to include('content_type: "text/plain; charset=utf-8"')
  end

  it "builds every artifact through the pure DocsKit::LlmsText builder" do
    expect(source).to include("DocsKit::LlmsText.index")
    expect(source).to include("DocsKit::LlmsText.pages")
    expect(source).to include("DocsKit::LlmsText.full")
  end

  it "HTTP-caches on the gem version + body via stale?/etag" do
    expect(source).to include("stale?(etag: [DocsKit::VERSION, body]")
  end

  it "sends a public max-age so a shared cache (dash-proxy, CDN) can store it" do
    # `public` alone is not storable under RFC 9111 — a shared cache needs a
    # freshness lifetime. expires_in adds max-age; stale? keeps `public`.
    expect(source).to include("expires_in LLMS_MAX_AGE, public: true")
    expect(source).to include("LLMS_MAX_AGE = 300")
  end

  it "does not shadow ActionController::Base#config (forgery delegates to it)" do
    # RequestForgeryProtection delegates allow_forgery_protection to #config, so
    # a `def config` on the controller breaks csrf_meta_tags when #full renders a
    # page's <head>. Guard the regression: the DocsKit config reader is #docs_config.
    expect(source).not_to match(/^\s*def config\b/)
    expect(source).to include("def docs_config = DocsKit.configuration")
  end

  it "wraps every action in the request's version scope (DocsKit::Scoping)" do
    expect(source).to include("include DocsKit::Scoping")
  end
end
