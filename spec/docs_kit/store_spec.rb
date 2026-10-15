# frozen_string_literal: true

require "securerandom"

# DocsKit::Store is the per-Ractor home of docs-kit's caches (the snapshot and
# OpenAPI caches). Ruby 3.4+ takes the Ractor.store_if_absent path; the
# Mutex-guarded fallback (3.3, engines without Ractor) is covered on every Ruby
# by stubbing the capability check.
RSpec.describe DocsKit::Store do
  def key = :"docs_kit_store_spec_#{SecureRandom.hex(4)}"

  it "builds a value once and returns the same object afterwards" do
    name = key
    first = described_class.fetch(name) { +"built" }

    expect(described_class.fetch(name) { +"rebuilt" }).to be(first)
  end

  it "caches a nil value instead of rebuilding it" do
    name = key
    builds = 0
    2.times { described_class.fetch(name) { builds += 1 and nil } }

    expect(builds).to eq(1)
  end

  it "needs an initializer block" do
    expect { described_class.fetch(key) }.to raise_error(ArgumentError, /needs an initializer block/)
  end

  context "without Ractor.store_if_absent (the Mutex fallback)" do
    before { allow(described_class).to receive(:native?).and_return(false) }

    it "builds a value once on the main Ractor" do
      name = key
      first = described_class.fetch(name) { Object.new }

      expect(described_class.fetch(name) { Object.new }).to be(first)
    end

    describe "under contention" do
      let(:name) { key }
      let(:subject_call) { -> { described_class.fetch(name) { Object.new } } }

      it_behaves_like "thread-safe under contention", threads: 16, iterations: 20, consistent: :identical
    end
  end

  it "reports the capability it runs on" do
    expected = defined?(Ractor) ? Ractor.respond_to?(:store_if_absent) : false

    expect(described_class.native?).to be(expected)
  end
end
