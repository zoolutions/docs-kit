# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

RSpec.describe DocsKit::Snapshot do
  let(:fixtures_root) { File.expand_path("../fixtures/snapshots", __dir__) }
  let(:version) { DocsKit::DocVersion.new(id: "1.0") }

  before do
    described_class.reset_cache!
    DocsKit.configure { |c| c.snapshots_path = fixtures_root }
  end

  def snapshot
    described_class.for(version, config: DocsKit.configuration)
  end

  describe ".for" do
    it "memoizes per version id (same instance across reads)" do
      first = snapshot

      expect(described_class.for(version, config: DocsKit.configuration)).to be(first)
    end

    it "re-reads when the manifest's mtime changes" do
      tmp = File.join(Dir.mktmpdir, "snapshots")
      FileUtils.mkdir_p(File.join(tmp, "1.0"))
      FileUtils.cp_r(Dir[File.join(fixtures_root, "1.0", "*")], File.join(tmp, "1.0"))
      DocsKit.configure { |c| c.snapshots_path = tmp }
      first = snapshot

      manifest = File.join(tmp, "1.0", "manifest.json")
      data = JSON.parse(File.read(manifest))
      data["registries"][0]["pages"].pop
      File.write(manifest, JSON.generate(data))
      FileUtils.touch(manifest, mtime: File.mtime(manifest) + 2)

      expect(snapshot).not_to be(first)
      expect(snapshot.all.map(&:slug)).to eq(%w[installation])
    end
  end

  describe "#all" do
    it "returns one entry per manifest page, in manifest order" do
      expect(snapshot.all.map(&:slug)).to eq(%w[installation configuration])
    end

    it "exposes the manifest attributes on each entry" do
      entry = snapshot.all.last

      expect(entry.title).to eq("Configuration")
      expect(entry.group).to eq("Getting started")
      expect(entry.icon).to eq("settings")
      expect(entry.digest).to start_with("9d2f")
    end

    it "prefixes every href with the version segment" do
      expect(snapshot.all.map(&:href))
        .to eq(%w[/1.0/docs/installation /1.0/docs/configuration])
    end
  end

  describe "#from_slug" do
    it "finds an entry by slug" do
      expect(snapshot.from_slug("installation").title).to eq("Installation")
    end

    it "is nil for an unknown slug" do
      expect(snapshot.from_slug("nope")).to be_nil
    end
  end

  describe "#nav_items" do
    it "groups NavItems like a registry, hrefs already version-prefixed" do
      items = snapshot.nav_items

      expect(items.keys).to eq(["Getting started"])
      expect(items["Getting started"].map(&:href))
        .to eq(%w[/1.0/docs/installation /1.0/docs/configuration])
      expect(items["Getting started"]).to all(be_a(DocsKit::NavItem))
    end
  end

  describe "#nav_groups" do
    it "keys nav_items by the manifest registry heading (the sidebar shape)" do
      groups = snapshot.nav_groups

      expect(groups.keys).to eq(["Docs"])
      expect(groups["Docs"]["Getting started"].map(&:label))
        .to eq(%w[Installation Configuration])
    end
  end

  describe "#path_prefix" do
    it "is the version-prefixed docs prefix" do
      expect(snapshot.path_prefix).to eq("/1.0/docs")
    end
  end

  describe "#markdown_for" do
    it "returns the raw snapshot file body" do
      expect(snapshot.markdown_for("installation")).to include("Add the gem to your Gemfile")
    end

    it "is nil for an unknown slug" do
      expect(snapshot.markdown_for("nope")).to be_nil
    end
  end

  describe "the archived-page duck type" do
    it "gives every entry a truthy view_class (the select(&:view_class) filter passes)" do
      expect(snapshot.all.map(&:view_class)).to all(eq(DocsUI::ArchivedPage))
    end

    it "builds an ArchivedPage renderable carrying the entry" do
      renderable = snapshot.from_slug("installation").renderable

      expect(renderable).to be_a(DocsUI::ArchivedPage)
    end

    it "reads the entry's markdown body from its snapshot file" do
      expect(snapshot.from_slug("installation").markdown).to include('gem "docs_kit"')
    end
  end

  describe "degrading to an empty snapshot" do
    it "is empty for a version with no snapshot directory (never raises)" do
      missing = described_class.for(DocsKit::DocVersion.new(id: "0.9"), config: DocsKit.configuration)

      expect(missing.all).to eq([])
      expect(missing.nav_items).to eq({})
      expect(missing.nav_groups).to eq({})
      expect(missing.markdown_for("installation")).to be_nil
    end

    it "is empty when no snapshots_path is configured" do
      DocsKit.reset_configuration!

      expect(snapshot.all).to eq([])
    end

    it "is empty for an unreadable manifest (never takes the site down)" do
      tmp = File.join(Dir.mktmpdir, "snapshots")
      FileUtils.mkdir_p(File.join(tmp, "1.0"))
      File.write(File.join(tmp, "1.0", "manifest.json"), "{not json")
      DocsKit.configure { |c| c.snapshots_path = tmp }

      expect(snapshot.all).to eq([])
    end
  end
end
