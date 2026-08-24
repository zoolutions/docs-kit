# frozen_string_literal: true

RSpec.describe DocsKit::DocVersion do
  it "carries id/label/ref and the current/noindex flags" do
    version = described_class.new(id: "1.0", label: "v1.0", ref: "v1.0.0", current: true, noindex: false)

    expect(version.id).to eq("1.0")
    expect(version.label).to eq("v1.0")
    expect(version.ref).to eq("v1.0.0")
    expect(version.current).to be(true)
    expect(version.noindex).to be(false)
  end

  it "defaults label to the id" do
    expect(described_class.new(id: "1.0").label).to eq("1.0")
  end

  it "defaults ref to nil and current to false" do
    version = described_class.new(id: "1.0")

    expect(version.ref).to be_nil
    expect(version.current).to be(false)
  end

  describe "#noindex" do
    it "defaults to true for an archived version (the inverse of current)" do
      expect(described_class.new(id: "1.0").noindex).to be(true)
    end

    it "defaults to false for the current version" do
      expect(described_class.new(id: "1.1", current: true).noindex).to be(false)
    end

    it "is explicitly overridable to false on an archived version" do
      expect(described_class.new(id: "1.0", noindex: false).noindex).to be(false)
    end
  end

  describe ".from" do
    it "returns a DocVersion unchanged" do
      version = described_class.new(id: "1.0")

      expect(described_class.from(version)).to be(version)
    end

    it "builds one from a symbol-keyed Hash" do
      version = described_class.from(id: "1.0", label: "v1.0", ref: "v1.0.0")

      expect(version.id).to eq("1.0")
      expect(version.label).to eq("v1.0")
      expect(version.ref).to eq("v1.0.0")
    end

    it "builds one from a string-keyed Hash (YAML/JSON config loads cleanly)" do
      version = described_class.from("id" => "1.1", "current" => true)

      expect(version.id).to eq("1.1")
      expect(version.current).to be(true)
      expect(version.noindex).to be(false)
    end
  end

  describe "#current? / #archived?" do
    it "is current when marked current" do
      version = described_class.new(id: "1.1", current: true)

      expect(version.current?).to be(true)
      expect(version.archived?).to be(false)
    end

    it "is archived otherwise" do
      version = described_class.new(id: "1.0")

      expect(version.current?).to be(false)
      expect(version.archived?).to be(true)
    end
  end

  describe "#path_prefix" do
    it "is empty for the current version (unprefixed URLs, unchanged sites)" do
      expect(described_class.new(id: "1.1", current: true).path_prefix).to eq("")
    end

    it "is /<id> for an archived version" do
      expect(described_class.new(id: "1.0").path_prefix).to eq("/1.0")
    end
  end
end
