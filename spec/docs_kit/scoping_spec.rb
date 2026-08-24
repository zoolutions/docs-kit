# frozen_string_literal: true

# DocsKit::Scoping wraps a gem controller's actions in the request's version
# scope (around_action :docs_scope). The real controllers are Rails-only, so the
# hook + the wrapper are exercised through a stand-in host that records the
# around_action registration and exposes params — the same pattern as the
# DocsKit::Controller spec.
RSpec.describe DocsKit::Scoping do
  def host_for(params)
    request_params = params
    Class.new do
      class << self
        attr_reader :around_actions

        def around_action(name)
          (@around_actions ||= []) << name
        end
      end

      include DocsKit::Scoping

      define_method(:params) { request_params }
    end
  end

  it "registers the docs_scope around_action on include" do
    expect(host_for({}).around_actions).to eq([:docs_scope])
  end

  describe "#docs_scope" do
    before do
      DocsKit.configure do |c|
        c.versions = [{ id: "1.1", current: true }, { id: "1.0" }]
      end
    end

    it "runs the action inside the requested version's scope, then restores" do
      host = host_for({ version: "1.0" }).new

      seen = nil
      host.send(:docs_scope) { seen = DocsKit::Scope.version }

      expect(seen.id).to eq("1.0")
      expect(DocsKit::Scope.version).to be_nil
    end

    it "falls back to the current version for an unknown :version param" do
      host = host_for({ version: "9.9" }).new

      seen = nil
      host.send(:docs_scope) { seen = DocsKit::Scope.version }

      expect(seen.id).to eq("1.1")
    end

    it "scopes to nil on an unversioned site" do
      DocsKit.reset_configuration!
      host = host_for({}).new

      seen = :unset
      host.send(:docs_scope) { seen = DocsKit::Scope.version }

      expect(seen).to be_nil
    end
  end
end
