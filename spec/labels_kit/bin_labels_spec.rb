# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "stringio"
require "tempfile"
require "yaml"

load File.expand_path("../../bin/labels", __dir__) unless defined?(Labels)

# A runner stand-in: records the argv it was handed and replays a canned stdout
# keyed by the first two argv words ("label list", "issue edit", …).
class FakeGhRunner
  attr_reader :calls

  def initialize(responses = {})
    @responses = responses
    @calls = []
  end

  def call(*args)
    @calls << args
    @responses[args.first(2).join(" ")].to_s
  end

  def commands = calls.map { |args| args.join(" ") }

  def mutations = calls.reject { |args| args[1] == "list" }
end

# bin/labels keeps .github/labels.yml and the labels on GitHub in agreement. It is
# part of the labels kit (LABELS_KIT.md): byte-identical in every zoolutions repo.
# Every `gh` call goes through an injected runner, so nothing here hits the network.
RSpec.describe "bin/labels" do # rubocop:disable RSpec/DescribeClass -- a CLI, not a class
  subject(:cli) { Labels::CLI.new(manifest:, runner:, out:) }

  let(:out)           { StringIO.new }
  let(:runner)        { FakeGhRunner.new(responses) }
  let(:responses)     { { "label list" => JSON.generate(remote_labels) } }
  let(:remote_labels) { [] }
  let(:manifest)      { write_manifest }

  def write_manifest(labels: default_labels, paths: default_paths, ignore: ["size:*"])
    file = Tempfile.new(["labels", ".yml"])
    file.write(YAML.dump("ignore" => ignore, "labels" => labels, "paths" => paths))
    file.close
    file.path
  end

  def default_labels
    [
      { "name" => "bug", "color" => "d73a4a", "description" => "Something isn't working", "group" => "type" },
      { "name" => "chore", "color" => "ededed", "description" => "Tooling and config", "group" => "type" },
      { "name" => "client", "color" => "1d76db", "description" => "The browser runtime", "group" => "area" },
      { "name" => "devops", "color" => "006b75", "description" => "CI and release", "group" => "area" }
    ]
  end

  def default_paths
    { "app/javascript/**/*" => "client", ".github/**/*" => "devops" }
  end

  def lines = out.string.split("\n")

  describe "sync --dry-run" do
    let(:remote_labels) do
      [
        { "name" => "bug", "color" => "d73a4a", "description" => "Something isn't working" },
        { "name" => "client", "color" => "1d76db", "description" => "" },
        { "name" => "bugfix", "color" => "5e49f7", "description" => "Legacy" },
        { "name" => "size:M", "color" => "ededed", "description" => "" }
      ]
    end

    it "prints the create/update/delete plan without mutating anything" do
      expect(cli.call(["sync", "--dry-run"])).to eq(0)

      expect(out.string).to include("create chore", "update client", "delete bugfix")
      expect(runner.mutations).to be_empty
    end

    it "leaves labels matching an ignore: glob alone" do
      cli.call(["sync", "--dry-run"])

      expect(out.string).not_to include("size:M")
    end

    it "reports the deletions as pending until --delete is passed" do
      cli.call(["sync", "--dry-run"])

      expect(out.string).to include("pass --delete to remove")
    end

    it "treats a colour that differs only in case as matching" do
      remote_labels[0]["color"] = "D73A4A"
      cli.call(["sync", "--dry-run"])

      expect(out.string).not_to include("update bug")
    end

    context "when GitHub already matches the manifest" do
      let(:remote_labels) { default_labels.map { |label| label.except("group") } }

      it "prints nothing to do" do
        expect(cli.call(["sync", "--dry-run"])).to eq(0)
        expect(out.string).to include("nothing to do")
      end
    end
  end

  describe "sync" do
    let(:remote_labels) do
      [
        { "name" => "bug", "color" => "d73a4a", "description" => "Something isn't working" },
        { "name" => "client", "color" => "1d76db", "description" => "" },
        { "name" => "bugfix", "color" => "5e49f7", "description" => "Legacy" }
      ]
    end

    it "creates missing labels and updates drifted ones" do
      expect(cli.call(["sync"])).to eq(0)

      expect(runner.commands).to include(
        "label create chore --color ededed --description Tooling and config",
        "label edit client --color 1d76db --description The browser runtime"
      )
    end

    it "leaves an identical label untouched" do
      cli.call(["sync"])

      expect(runner.commands.grep(/label (create|edit) bug/)).to be_empty
    end

    it "does not delete anything without --delete" do
      cli.call(["sync"])

      expect(runner.commands.grep(/label delete/)).to be_empty
    end

    describe "--delete" do
      let(:responses) do
        {
          "label list" => JSON.generate(remote_labels),
          "issue list" => JSON.generate(open_issues),
          "pr list" => JSON.generate(open_prs)
        }
      end

      def open_issues = []

      def open_prs = []

      context "when the label is still on any item, open or closed" do
        def open_issues = [{ "number" => 101 }]

        def open_prs = [{ "number" => 199 }]

        it "refuses, names the items, and deletes nothing — deletion would strip closed history too" do
          expect(cli.call(["sync", "--delete"])).to eq(1)

          expect(out.string).to include("bugfix", "#101", "#199")
          expect(runner.commands.grep(/label delete/)).to be_empty
        end

        it "still applies the creates and updates — the refusal is per label" do
          cli.call(["sync", "--delete"])

          expect(runner.commands).to include("label create chore --color ededed --description Tooling and config")
        end
      end

      context "when the label name has a comma" do
        let(:remote_labels) { [{ "name" => "a,b", "color" => "ededed", "description" => "" }] }

        it "refuses to delete it rather than trusting an empty lookup" do
          expect(cli.call(["sync", "--delete"])).to eq(1)

          expect(runner.commands.grep(/label delete/)).to be_empty
        end
      end

      context "when the label is unused" do
        it "deletes it after checking open issues and pull requests" do
          expect(cli.call(["sync", "--delete"])).to eq(0)

          expect(runner.commands).to include(
            "issue list --state all --label bugfix --json number --limit 500",
            "pr list --state all --label bugfix --json number --limit 500",
            "label delete bugfix --yes"
          )
        end
      end
    end
  end

  describe "infer" do
    it "maps paths to the area labels declared in the manifest" do
      expect(cli.call(["infer", "app/javascript/phlex/reactive.js", ".github/workflows/ci.yml"])).to eq(0)

      expect(lines).to eq(%w[client devops])
    end

    it "strips a leading ./ and deduplicates across paths" do
      cli.call(["infer", "./app/javascript/a.js", "app/javascript/b/c.js"])

      expect(lines).to eq(["client"])
    end

    it "prints nothing for a path no glob claims, and never calls gh" do
      expect(cli.call(["infer", "lib/thing.rb"])).to eq(0)

      expect(out.string).to be_empty
      expect(runner.calls).to be_empty
    end

    context "with a manifest whose glob ends in a bare **" do
      let(:manifest) { write_manifest(paths: { "app/**/client/**" => "client" }) }

      it "still matches below the first segment" do
        cli.call(["infer", "app/javascript/client/deep/file.js"])

        expect(lines).to eq(["client"])
      end
    end

    context "with a {a,b} alternation glob" do
      let(:manifest) { write_manifest(paths: default_paths.merge("{AGENTS,CLAUDE}.md" => "dx")) }

      it "matches either top-level file" do
        cli.call(["infer", "CLAUDE.md"])

        expect(lines).to eq(["dx"])
      end
    end
  end

  describe "migrate" do
    let(:responses) do
      {
        "issue list" => JSON.generate([{ "number" => 101 }, { "number" => 90 }]),
        "pr list" => JSON.generate([{ "number" => 150 }])
      }
    end

    it "adds the replacements and removes the old label from every issue and pull request" do
      expect(cli.call(%w[migrate bugfix bug])).to eq(0)

      expect(runner.commands).to include(
        "issue edit 101 --add-label bug --remove-label bugfix",
        "issue edit 90 --add-label bug --remove-label bugfix",
        "pr edit 150 --add-label bug --remove-label bugfix"
      )
    end

    it "looks at closed items too — deleting a label strips it from those as well" do
      cli.call(%w[migrate bugfix bug])

      expect(runner.commands).to include(
        "issue list --state all --label bugfix --json number --limit 500",
        "pr list --state all --label bugfix --json number --limit 500"
      )
    end

    it "reports what it touched" do
      cli.call(%w[migrate bugfix bug])

      expect(out.string).to include("#101", "#150", "3 item(s)")
    end

    context "when nothing carries the old label" do
      let(:responses) { { "issue list" => "[]", "pr list" => "[]" } }

      it "says so and edits nothing" do
        expect(cli.call(%w[migrate bugfix bug])).to eq(0)

        expect(out.string).to include("nothing to migrate")
        expect(runner.commands.grep(/edit/)).to be_empty
      end
    end

    it "refuses a label whose name has a comma — gh --label would split it and find nothing" do
      expect(cli.call(["migrate", "needs info, maybe", "needs-info"])).to eq(1)

      expect(out.string).to include("comma")
      expect(runner.calls).to be_empty
    end

    it "requires at least one replacement label" do
      expect(cli.call(%w[migrate bugfix])).to eq(1)

      expect(out.string).to include("usage")
    end
  end

  describe "validate" do
    it "passes a well-formed manifest without calling gh" do
      expect(cli.call(["validate"])).to eq(0)

      expect(out.string).to include("4 label(s)")
      expect(runner.calls).to be_empty
    end

    {
      "a label with no description" => [{ "name" => "x", "color" => "ededed", "group" => "type" }],
      "an unknown group" => [{ "name" => "x", "color" => "ededed", "description" => "X", "group" => "misc" }],
      "an upper-case colour" => [{ "name" => "x", "color" => "EDEDED", "description" => "X", "group" => "type" }],
      "a duplicate name" => [{ "name" => "bug", "color" => "ededed", "description" => "X", "group" => "type" }]
    }.each do |problem, extra|
      context "with #{problem}" do
        let(:manifest) { write_manifest(labels: default_labels + extra) }

        it "fails" do
          expect(cli.call(["validate"])).to eq(1)
        end
      end
    end

    context "with a path mapped onto a label that is not an area" do
      let(:manifest) { write_manifest(paths: { "lib/**/*" => "bug" }) }

      it "fails and names the glob" do
        expect(cli.call(["validate"])).to eq(1)

        expect(out.string).to include("lib/**/*")
      end
    end

    context "with no area labels" do
      let(:manifest) { write_manifest(labels: default_labels.first(2), paths: {}) }

      it "fails — every pull request needs at least one area" do
        expect(cli.call(["validate"])).to eq(1)
      end
    end
  end

  describe "argument handling" do
    it "rejects an unknown subcommand" do
      expect(cli.call(["frobnicate"])).to eq(1)

      expect(out.string).to include("usage")
    end
  end

  # The commands run bin/labels as a bare `ruby` process from the repo root.
  describe "as a standalone script" do
    def root = File.expand_path("../..", __dir__)

    it "runs against this repo's own manifest" do
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "bin/labels", "validate", chdir: root)

      expect(stderr).not_to match(/Error|undefined/)
      expect(status).to be_success
    end

    it "infers areas from this repo's path map" do
      stdout, _stderr, status = Open3.capture3(RbConfig.ruby, "bin/labels", "infer", ".github/workflows/ci.yml",
                                               chdir: root)

      expect(status).to be_success
      expect(stdout.split("\n")).to eq(["devops"])
    end
  end
end
