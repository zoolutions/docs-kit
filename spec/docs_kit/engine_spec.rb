# frozen_string_literal: true

require "rails"
require "docs_kit/engine"

# The engine's docs_kit.importmap initializer, run against a stand-in app config
# (no Rails boot). config.docs_kit.auto_pin = false lets a host with its own
# docs import map keep the gem's pin out of the shared one.
RSpec.describe DocsKit::Engine do
  let(:pin_file) { described_class.root.join("config/importmap.rb") }
  let(:importmap_config) { ActiveSupport::OrderedOptions.new.merge!(paths: [], cache_sweepers: []) }
  let(:docs_kit_config) { ActiveSupport::OrderedOptions.new.merge!(auto_pin: true) }
  let(:app) do
    config = Struct.new(:importmap, :docs_kit).new(importmap_config, docs_kit_config)
    Struct.new(:config).new(config)
  end

  def run_importmap_initializer
    described_class.instance.initializers.find { |i| i.name == "docs_kit.importmap" }.run(app)
  end

  it "defaults config.docs_kit.auto_pin to true" do
    expect(described_class.config.docs_kit.auto_pin).to be(true)
  end

  it "adds the gem's pins to the host import map by default" do
    run_importmap_initializer

    expect(importmap_config.paths).to include(pin_file)
    expect(importmap_config.cache_sweepers).to include(described_class::JAVASCRIPT_PATH)
  end

  describe "the docs_kit.finalize initializer" do
    let(:after_initialize_hooks) { [] }

    # A stand-in app config that records after_initialize blocks.
    def boot(reloading:)
      hooks = after_initialize_hooks
      config = Object.new
      config.define_singleton_method(:after_initialize) { |&block| hooks << block }
      config.define_singleton_method(:reloading_enabled?) { reloading }
      initializer = described_class.instance.initializers.find { |i| i.name == "docs_kit.finalize" }
      initializer.run(Struct.new(:config).new(config))
      hooks.each(&:call)
    end

    before { allow(DocsKit).to receive(:finalize!) }

    it "finalizes the configuration after the host has configured it" do
      boot(reloading: false)

      expect(DocsKit).to have_received(:finalize!)
    end

    it "leaves it open while code reloading is on (development)" do
      boot(reloading: true)

      expect(DocsKit).not_to have_received(:finalize!)
    end
  end

  it "leaves the host import map alone when auto_pin is false" do
    docs_kit_config.auto_pin = false
    run_importmap_initializer

    expect(importmap_config.paths).not_to include(pin_file)
    expect(importmap_config.cache_sweepers).to be_empty
  end
end
