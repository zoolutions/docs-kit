# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

# script/labels-kit keeps the shared label files (bin/labels, .github/LABELS.md)
# identical across the zoolutions repos and checks each repo's own manifest
# carries the shared labels unchanged. These specs run it against throwaway repos.
RSpec.describe "script/labels-kit" do # rubocop:disable RSpec/DescribeClass -- a CLI, not a class
  let(:tmp) { Dir.mktmpdir }
  let(:target) { File.join(tmp, "demo") }

  before { FileUtils.mkdir_p(File.join(target, ".github")) }
  after { FileUtils.rm_rf(tmp) }

  def root = File.expand_path("../..", __dir__)

  def run_kit(*args) = Open3.capture2e(File.join(root, "script/labels-kit"), *args)

  def canonical_manifest = YAML.safe_load_file(File.join(root, ".github/labels.yml"))

  def read_target(path) = File.read(File.join(target, path))

  def target_manifest = YAML.safe_load_file(File.join(target, ".github/labels.yml"))

  def write_manifest(data) = File.write(File.join(target, ".github/labels.yml"), YAML.dump(data))

  # A repo manifest: the shared labels and the shared areas that apply (no docs
  # app here, so no docs-site) unchanged, plus one area of its own.
  def repo_manifest
    applicable = %w[devops dx]
    shared = canonical_manifest["labels"].select do |label|
      label["group"] != "area" || applicable.include?(label["name"])
    end
    own = { "name" => "widgets", "color" => "1d76db", "description" => "The widget kit", "group" => "area" }
    { "ignore" => [], "labels" => shared + [own], "paths" => { "lib/widgets/**/*" => "widgets" } }
  end

  describe "sync" do
    it "copies bin/labels (executable) and .github/LABELS.md verbatim" do
      _out, status = run_kit("sync", target)

      expect(status).to be_success
      expect(read_target("bin/labels")).to eq(File.read(File.join(root, "bin/labels")))
      expect(File.executable?(File.join(target, "bin/labels"))).to be(true)
      expect(read_target(".github/LABELS.md")).to eq(File.read(File.join(root, ".github/LABELS.md")))
    end

    it "writes a starter manifest with the shared labels when the repo has none" do
      out, status = run_kit("sync", target)

      expect(status).to be_success

      names = target_manifest["labels"].map { |label| label["name"] }
      expect(names).to include("bug", "chore", "plan", "devops", "dx")
      expect(names).not_to include("components", "docs-site")
      expect(out).to include("add this repo's own area labels")
    end

    it "leaves an existing manifest alone — it is the repo's own" do
      write_manifest(repo_manifest)

      _out, status = run_kit("sync", target)

      expect(status).to be_success
      expect(target_manifest).to eq(repo_manifest)
    end

    it "adds docs-site to the starter only when the repo has a docs app" do
      FileUtils.mkdir_p(File.join(target, "docs"))
      File.write(File.join(target, "docs/Gemfile"), "")

      run_kit("sync", target)

      expect(target_manifest["labels"].map { |label| label["name"] }).to include("docs-site")
    end
  end

  describe "check" do
    before do
      _out, status = run_kit("sync", target)
      raise "sync failed" unless status.success?

      write_manifest(repo_manifest)
    end

    it "passes a repo that matches the kit" do
      out, status = run_kit("check", target)

      expect(status).to be_success
      expect(out).to include("demo: in sync")
    end

    it "fails on a drifted shared file" do
      File.write(File.join(target, "bin/labels"), "# edited locally\n", mode: "a")

      out, status = run_kit("check", target)

      expect(status).not_to be_success
      expect(out).to include("bin/labels differs")
    end

    it "fails when a shared label is missing or reworded" do
      data = repo_manifest
      data["labels"].reject! { |label| label["name"] == "chore" }
      data["labels"].find { |label| label["name"] == "bug" }["description"] = "Broken"
      write_manifest(data)

      out, status = run_kit("check", target)

      expect(status).not_to be_success
      expect(out).to include("shared label chore is missing", "shared label bug differs")
    end

    it "fails when a shared area that applies is missing" do
      data = repo_manifest
      data["labels"].reject! { |label| label["name"] == "dx" }
      write_manifest(data)

      out, status = run_kit("check", target)

      expect(status).not_to be_success
      expect(out).to include("shared label dx is missing")
    end

    it "fails on an extra label in a shared group" do
      data = repo_manifest
      data["labels"] << { "name" => "bugfix", "color" => "ededed", "description" => "Dup", "group" => "type" }
      write_manifest(data)

      out, status = run_kit("check", target)

      expect(status).not_to be_success
      expect(out).to include("bugfix is not a shared type label")
    end

    it "reports an unparseable manifest as a problem instead of crashing" do
      File.write(File.join(target, ".github/labels.yml"), "labels: [unclosed\n")

      out, status = run_kit("check", target, target)

      expect(status).not_to be_success
      expect(out).to include("labels.yml is not valid YAML")
      expect(out).not_to include("Psych")
    end

    it "reports a manifest whose top level is a list instead of crashing" do
      File.write(File.join(target, ".github/labels.yml"), "- name: bug\n")

      out, status = run_kit("check", target)

      expect(status).not_to be_success
      expect(out).to include("must be a mapping with a labels list")
      expect(out).not_to include("TypeError")
    end

    it "fails when the repo's manifest does not validate" do
      data = repo_manifest
      data["paths"]["lib/**/*"] = "bug"
      write_manifest(data)

      out, status = run_kit("check", target)

      expect(status).not_to be_success
      expect(out).to include("maps to bug")
    end
  end
end
