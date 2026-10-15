# frozen_string_literal: true

RSpec.describe DocsKit::Shareable do
  it "deep-freezes a nested literal into a Ractor-shareable value" do
    skip "no Ractor on this engine" unless defined?(Ractor)
    value = described_class.make({ note: { klass: +"alert-info" } })

    expect(Ractor.shareable?(value)).to be(true)
    expect(value[:note][:klass]).to be_frozen
  end

  it "makes a capture-free lambda shareable and keeps it callable" do
    skip "no Ractor on this engine" unless defined?(Ractor)
    # Built in a class method, so its self (the class) is shareable — as for a
    # lambda in a constant.
    nav = Class.new { def self.nav = DocsKit::Shareable.make(-> { {} }) }.nav

    expect(Ractor.shareable?(nav)).to be(true)
    expect(nav.call).to eq({})
  end

  it "falls back to a plain freeze on an engine without Ractor.make_shareable" do
    if defined?(Ractor)
      allow(Ractor).to receive(:respond_to?).and_call_original
      allow(Ractor).to receive(:respond_to?).with(:make_shareable).and_return(false)
    end
    inner = +"alert-info"
    value = described_class.make({ klass: inner })

    expect(value).to be_frozen
    expect(inner).not_to be_frozen
  end
end
