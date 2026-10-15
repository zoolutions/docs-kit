# frozen_string_literal: true

require "json"

# DocsKit::Snapshot.for is called on every archived-version request, from every
# server thread. Its cache is a check-then-set: a cold key must be built (read +
# JSON.parse the manifest) exactly once, however many threads miss it together.
# The JSON.parse spy yields the thread (Thread.pass) inside the build, which is
# the race window: an unguarded cache lets every waiting thread miss and parse.
RSpec.describe DocsKit::Snapshot do
  let(:fixtures_root) { File.expand_path("../fixtures/snapshots", __dir__) }
  let(:version) { DocsKit::DocVersion.new(id: "1.0") }

  before do
    described_class.reset_cache!
    DocsKit.configure { |c| c.snapshots_path = fixtures_root }
  end

  def cold_load_from(threads)
    start = Queue.new
    workers = Array.new(threads) do
      Thread.new do
        start.pop
        described_class.for(version, config: DocsKit.configuration)
      end
    end
    threads.times { start << true }
    workers.map(&:value)
  end

  it "parses the manifest once when 32 threads cold-load the same version" do
    parses = Queue.new
    allow(JSON).to receive(:parse).and_wrap_original do |original, *args, **kwargs|
      parses << true
      Thread.pass
      original.call(*args, **kwargs)
    end

    snapshots = cold_load_from(32)

    expect(parses.size).to eq(1)
    expect(snapshots.uniq(&:object_id).size).to eq(1)
  end

  describe "concurrent reads" do
    let(:subject_call) { -> { described_class.for(version, config: DocsKit.configuration) } }

    it_behaves_like "thread-safe under contention", threads: 16, iterations: 20, consistent: :identical
  end
end
