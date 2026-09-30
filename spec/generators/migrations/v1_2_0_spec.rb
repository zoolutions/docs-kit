# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "generators/docs_kit/install/migration"
require "generators/docs_kit/install/migration_registry"
require "generators/docs_kit/install/migrations/v1_2_0"

# The 1.1 → 1.2 upgrade, run by `rails g docs_kit:install --sync`. Warn-only-safe:
# it rewrites a value only when it is exactly what an older docs-kit generated
# (so it can't be a hand edit) and hands everything else back as a warning.
RSpec.describe DocsKit::Generators::Migrations::V1_2_0 do
  subject(:warnings) { described_class.call(root) }

  let(:root) { Dir.mktmpdir }

  after { FileUtils.rm_rf(root) }

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(File.join(root, path)))
    File.write(File.join(root, path), content)
  end

  def read(path) = File.read(File.join(root, path))

  def package_json(dev_dependencies)
    JSON.pretty_generate("private" => true, "devDependencies" => dev_dependencies)
  end

  it "is registered as the 1.2.0 migration" do
    registry = DocsKit::Generators::MigrationRegistry.default

    expect(registry.applicable("1.1.1", upto: "1.2.0").map(&:description)).to include(described_class::DESCRIPTION)
  end

  it "does nothing and warns about nothing on a site without these files" do
    expect(warnings).to be_empty
  end

  describe "Dockerfile Bun version" do
    it "bumps the Bun an older docs-kit generated" do
      write("Dockerfile", "ARG RUBY_VERSION=3.4.7\nARG BUN_VERSION=1.3.2\n")

      warnings

      expect(read("Dockerfile")).to include("ARG BUN_VERSION=1.4.2")
    end

    it "warns about (never rewrites) a hand-picked older Bun" do
      write("Dockerfile", "ARG RUBY_VERSION=3.4.7\nARG BUN_VERSION=1.2.9\n")

      expect(warnings).to include(a_string_including("BUN_VERSION=1.2.9", "1.4.2"))
      expect(read("Dockerfile")).to include("ARG BUN_VERSION=1.2.9")
    end

    it "leaves a newer Bun alone" do
      write("Dockerfile", "ARG RUBY_VERSION=3.4.7\nARG BUN_VERSION=1.5.0\n")

      expect(warnings).to be_empty
      expect(read("Dockerfile")).to include("ARG BUN_VERSION=1.5.0")
    end
  end

  describe "Ruby floor (docs-kit 1.2 requires Ruby >= 3.3)" do
    it "warns about a Dockerfile building on Ruby 3.2" do
      write("Dockerfile", "ARG RUBY_VERSION=3.2.8\nARG BUN_VERSION=1.4.2\n")

      expect(warnings).to include(a_string_including("RUBY_VERSION=3.2.8", "3.3"))
    end

    it "warns about a .ruby-version below 3.3" do
      write(".ruby-version", "ruby-3.2.4\n")

      expect(warnings).to include(a_string_including(".ruby-version", "3.2.4"))
    end

    it "accepts Ruby 3.3 and newer" do
      write(".ruby-version", "3.4.11\n")
      write("Dockerfile", "ARG RUBY_VERSION=3.3.9\nARG BUN_VERSION=1.4.2\n")

      expect(warnings).to be_empty
    end
  end

  describe "package.json toolchain floors" do
    it "raises the floors an older docs-kit generated" do
      write("package.json", package_json("@tailwindcss/cli" => "^4.1.18", "daisyui" => "^5.6.0",
                                         "tailwindcss" => "^4.1.18"))

      warnings

      expect(JSON.parse(read("package.json"))["devDependencies"])
        .to eq("@tailwindcss/cli" => "^4.3.3", "daisyui" => "^5.7.47", "tailwindcss" => "^4.3.3")
    end

    it "keeps the rest of the file byte-for-byte" do
      original = %({\n  "private": true,\n  "scripts": { "build:css": "bin/build-css" },\n  ) +
                 %("devDependencies": {\n    "daisyui": "^5.6.0"\n  }\n}\n)
      write("package.json", original)

      warnings

      expect(read("package.json")).to eq(original.sub(%("^5.6.0"), %("^5.7.47")))
    end

    it "warns about a hand-picked lower floor" do
      write("package.json", package_json("daisyui" => "^5.2.0"))

      expect(warnings).to include(a_string_including("daisyui", "^5.2.0", "^5.7.47"))
      expect(read("package.json")).to include(%("daisyui": "^5.2.0"))
    end

    it "leaves an equal or higher floor alone" do
      write("package.json", package_json("daisyui" => "^5.8.0", "tailwindcss" => "^4.3.3"))

      expect(warnings).to be_empty
    end
  end

  describe "the reusable deploy workflow" do
    it "warns when a site pins docs-kit's deploy.yml to anything but main" do
      write(".github/workflows/deploy-docs.yml",
            "    uses: zoolutions/docs-kit/.github/workflows/deploy.yml@0123abc # pinned\n")

      expect(warnings).to include(a_string_including("deploy-docs.yml", "@0123abc"))
    end

    it "is quiet for a caller that tracks main" do
      write(".github/workflows/deploy-docs.yml", "    uses: zoolutions/docs-kit/.github/workflows/deploy.yml@main\n")

      expect(warnings).to be_empty
    end
  end
end
