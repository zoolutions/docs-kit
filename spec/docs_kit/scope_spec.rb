# frozen_string_literal: true

RSpec.describe DocsKit::Scope do
  let(:archived) { DocsKit::DocVersion.new(id: "1.0") }
  let(:current) { DocsKit::DocVersion.new(id: "1.1", current: true) }

  it "defaults to an empty scope (nil version, nil locale)" do
    expect(described_class.version).to be_nil
    expect(described_class.locale).to be_nil
  end

  it "has an empty path_prefix by default" do
    expect(described_class.path_prefix).to eq("")
  end

  describe ".with" do
    it "exposes the version inside the block and restores after" do
      described_class.with(version: archived) do
        expect(described_class.version).to be(archived)
      end

      expect(described_class.version).to be_nil
    end

    it "restores the previous scope when the block raises" do
      expect do
        described_class.with(version: archived) { raise "boom" }
      end.to raise_error("boom")

      expect(described_class.version).to be_nil
    end

    it "nests: the inner scope wins, then the outer is restored" do
      described_class.with(version: archived) do
        described_class.with(version: current) do
          expect(described_class.version).to be(current)
        end

        expect(described_class.version).to be(archived)
      end
    end

    it "returns the block's value" do
      expect(described_class.with(version: archived) { :result }).to eq(:result)
    end

    it "leaks nothing across sequential calls" do
      described_class.with(version: archived) { nil }
      described_class.with(locale: :de) { nil }

      expect(described_class.version).to be_nil
      expect(described_class.locale).to be_nil
    end

    it "carries the reserved locale slot (i18n M2 — nothing reads it yet)" do
      described_class.with(locale: :de) do
        expect(described_class.locale).to eq(:de)
      end
    end
  end

  describe ".path_prefix" do
    it "is the in-scope version's prefix" do
      described_class.with(version: archived) do
        expect(described_class.path_prefix).to eq("/1.0")
      end
    end

    it "is empty for the current version" do
      described_class.with(version: current) do
        expect(described_class.path_prefix).to eq("")
      end
    end
  end
end
