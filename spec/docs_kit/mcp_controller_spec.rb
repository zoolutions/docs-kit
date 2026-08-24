# frozen_string_literal: true

# Like DocsKit::LlmsController/SearchController, DocsKit::McpController subclasses
# ActionController::Base, so it can't load in the standalone suite (no Rails
# request stack). Its real behavior — the JSON-RPC round-trip — is proven by
# spec/docs_kit/mcp_server_spec.rb (the server it delegates to) and dogfooded
# against the docs/ app. Here we prove the SHIPPED FILE is where Rails autoloads
# DocsKit::McpController from, and that the thin controller wires the server, the
# CSRF/optional-gem gates, and the read-only method policy correctly.
# rubocop:disable-next RSpec/DescribeClass -- the class is Rails-only, can't constantize here
RSpec.describe "DocsKit::McpController (source wiring)" do
  # app/controllers/docs_kit/mcp_controller.rb → DocsKit::McpController under
  # Rails' default inflector, the same path/loader story as LlmsController.
  let(:path) do
    File.expand_path("../../app/controllers/docs_kit/mcp_controller.rb", __dir__)
  end
  let(:source) { File.read(path) }

  it "ships at the path Rails autoloads DocsKit::McpController from" do
    expect(File.exist?(path)).to be(true)
  end

  it "declares DocsKit::McpController < ActionController::Base" do
    expect(source).to include("module DocsKit")
    expect(source).to include("class McpController < ActionController::Base")
  end

  it "exposes the POST JSON-RPC action" do
    expect(source).to match(/def create\b/)
  end

  it "delegates the JSON-RPC to DocsKit::McpServer over the request body" do
    expect(source).to include("DocsKit::McpServer.build")
    expect(source).to include("handle_json(request.body.read)")
  end

  it "renders application/json (the JSON-RPC content type)" do
    expect(source).to include("application/json")
  end

  it "skips CSRF (a JSON-RPC POST carries no forgery token)" do
    expect(source).to include("skip_forgery_protection")
  end

  it "gates the endpoint on mcp_enabled? (off → not found, byte-identical to no feature)" do
    expect(source).to include("mcp_enabled?")
  end

  it "returns 405 for the non-POST verbs (read-only, stateless — no SSE session)" do
    expect(source).to match(/def method_not_allowed\b/)
    expect(source).to include(":method_not_allowed")
  end

  it "does not shadow ActionController::Base#config (forgery delegates to it)" do
    # Same guard as LlmsController: a `def config` on a gem controller reroutes
    # RequestForgeryProtection's delegations. The DocsKit config reader is #docs_config.
    expect(source).not_to match(/^\s*def config\b/)
    expect(source).to include("def docs_config = DocsKit.configuration")
  end

  it "wraps every action in the request's version scope (DocsKit::Scoping)" do
    expect(source).to include("include DocsKit::Scoping")
  end
end
