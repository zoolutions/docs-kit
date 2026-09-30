# frozen_string_literal: true

require "rake"
require "tmpdir"

load File.expand_path("../../rakelib/release.rake", __dir__)

RSpec.describe ReleaseKit do
  let(:lock) do
    <<~LOCK
      PATH
        remote: ..
        specs:
          docs-kit (1.1.1)
            daisyui (>= 1.2, < 2)

      GEM
        remote: https://rubygems.org/
        specs:
          docs-kit-extras (0.4.0)
            docs-kit (>= 1.0, < 2)

      DEPENDENCIES
        docs-kit!
        docs-kit-extras

      CHECKSUMS
        docs-kit (1.1.1)
        docs-kit-extras (0.4.0) sha256=abc
    LOCK
  end

  describe "the release task" do
    around do |example|
      original = Rake.application
      Rake.application = Rake::Application.new
      example.run
    ensure
      Rake.application = original
    end

    # `require "bundler/gem_tasks"` defines its own `release` (tag push + a local
    # `gem push`). Rake would MERGE a second definition into it, running both.
    it "replaces an existing release task instead of merging into it" do
      Rake::Task.define_task(:build)
      Rake::Task.define_task(release: :build) { raise "bundler's release ran" }

      load File.expand_path("../../rakelib/release.rake", __dir__)

      release = Rake::Task[:release]
      expect(release.prerequisites).to be_empty
      expect(release.actions.size).to eq(1)
      expect(release.arg_names).to eq(%i[version force])
    end
  end

  describe ".pins" do
    it "finds the PATH spec and the CHECKSUMS entry, not dependency requirements or look-alike gems" do
      expect(described_class.pins(lock, "docs-kit")).to eq(%w[1.1.1 1.1.1])
    end
  end

  describe ".bump_pins" do
    subject(:bumped) { described_class.bump_pins(lock, "docs-kit", "1.2.0") }

    it "rewrites both pins to the new version" do
      expect(described_class.pins(bumped, "docs-kit")).to eq(%w[1.2.0 1.2.0])
    end

    it "leaves requirements and other gems untouched" do
      expect(bumped).to include("      docs-kit (>= 1.0, < 2)", "    docs-kit-extras (0.4.0)", "  docs-kit!")
    end

    it "changes nothing but the two pin lines" do
      changed = lock.lines.zip(bumped.lines).reject { |before, after| before == after }
      expect(changed.map(&:last)).to eq(["    docs-kit (1.2.0)\n", "  docs-kit (1.2.0)\n"])
    end
  end

  describe ".sources_gem?" do
    it "is true when DEPENDENCIES lists the gem as locally sourced" do
      expect(described_class.sources_gem?(lock, "docs-kit")).to be(true)
    end

    it "is false for a gem that is only a rubygems dependency" do
      expect(described_class.sources_gem?(lock, "docs-kit-extras")).to be(false)
    end
  end

  context "when run inside a gem checkout" do
    around do |example|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p(%w[lib/demo docs])
          File.write("lib/demo/version.rb", %(module Demo\n  VERSION = "0.3.0"\nend\n))
          File.write("lib/demo/doc_version.rb", %(module Demo\n  DOC_VERSION = "0.3.0"\nend\n))
          File.write("demo.gemspec", "")
          File.write(".gitignore", "/Gemfile.lock\n")
          File.write("Gemfile.lock", "ignored")
          File.write("docs/Gemfile.lock", "tracked")
          system("git init -q && git add -A", exception: true)
          example.run
        end
      end
    end

    it "finds the gemspec" do
      expect(described_class.gemspec).to eq("demo.gemspec")
    end

    it "finds the version.rb holding the current VERSION" do
      expect(described_class.version_file("0.3.0")).to eq("lib/demo/version.rb")
    end

    it "lists tracked lockfiles only, never an ignored one" do
      expect(described_class.tracked_lockfiles).to eq(["docs/Gemfile.lock"])
    end

    describe ".lockfiles_sourcing" do
      it "returns the tracked locks that source the gem, with their content" do
        File.write("docs/Gemfile.lock", "PATH\n  specs:\n    demo (0.3.0)\n\nDEPENDENCIES\n  demo!\n")

        expect(described_class.lockfiles_sourcing("demo").keys).to eq(["docs/Gemfile.lock"])
      end

      it "skips a tracked lock that does not source the gem" do
        expect(described_class.lockfiles_sourcing("demo")).to be_empty
      end

      it "aborts, before any write, when a lock sources the gem but carries no pin" do
        File.write("docs/Gemfile.lock", "DEPENDENCIES\n  demo!\n")

        expect { described_class.lockfiles_sourcing("demo") }
          .to raise_error(SystemExit).and output(/sources demo but has no/).to_stderr
      end
    end
  end
end
