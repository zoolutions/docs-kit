# frozen_string_literal: true

require "securerandom"

# docs-kit runs under Puma (threads) and Falcon (fibers in one reactor). The
# request-scoped content scope (DocsKit::Scope) must stay per request on both,
# and an archived-version request reads its sidebar through the shared
# DocsKit::Snapshot cache. Each call yields mid-request (Thread.pass between
# threads, Async::Task#yield between fibers) so other requests run inside it.
RSpec.describe "docs-kit under a threaded or fibered server" do # rubocop:disable RSpec/DescribeClass
  # A point where another thread or Async task runs.
  let(:interleave) do
    lambda do
      task = defined?(Async::Task) && Async::Task.current?
      task ? task.yield : Thread.pass
    end
  end

  describe "DocsKit::Scope.with" do
    # Scopes its own version, lets the others run, reads its own back, and
    # leaves no scope behind.
    let(:subject_call) do
      pass = interleave
      lambda do
        mine = DocsKit::DocVersion.new(id: SecureRandom.hex(4))
        inside = DocsKit::Scope.with(version: mine) do
          pass.call
          DocsKit::Scope.version
        end
        inside.equal?(mine) && DocsKit::Scope.version.nil?
      end
    end

    # Every call kept its own scope.
    it_behaves_like "thread-safe under contention", consistent: ->(results) { results.all?(true) }
    it_behaves_like "fiber-safe under an Async reactor", consistent: ->(results) { results.all?(true) }
  end

  describe "an archived-version sidebar (DocsKit::Snapshot.for)" do
    let(:archived) { DocsKit::DocVersion.new(id: "1.0") }
    let(:subject_call) do
      version = archived
      pass = interleave
      lambda do
        DocsKit::Scope.with(version: version) do
          pass.call
          [DocsKit::Snapshot.for(version), DocsKit.configuration.nav_groups]
        end
      end
    end

    before do
      DocsKit::Snapshot.reset_cache!
      DocsKit.configure do |c|
        c.versions = [{ id: "1.1", current: true }, { id: "1.0" }]
        c.snapshots_path = File.expand_path("../fixtures/snapshots", __dir__)
      end
    end

    # One snapshot instance for every request, and the same sidebar.
    it_behaves_like "thread-safe under contention",
                    consistent: ->(results) { results.map(&:first).uniq(&:object_id).one? && results.uniq(&:last).one? }
    it_behaves_like "fiber-safe under an Async reactor",
                    consistent: ->(results) { results.map(&:first).uniq(&:object_id).one? && results.uniq(&:last).one? }
  end
end
