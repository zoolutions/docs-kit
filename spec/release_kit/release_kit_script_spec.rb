# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

# script/release-kit keeps the shared release files (bin/release,
# rakelib/release.rake, the shared jobs of release.yml) identical across the
# zoolutions gems. These specs run it against throwaway target repos.
RSpec.describe "script/release-kit" do # rubocop:disable RSpec/DescribeClass -- a CLI, not a class
  let(:tmp) { Dir.mktmpdir }
  let(:target) { File.join(tmp, "demo") }
  let(:custom_test_job) do
    "  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bundle install\n#{frozen_install}      " \
      "- run: bundle exec my-own-suite\n"
  end

  before { FileUtils.mkdir_p(File.join(target, ".github/workflows")) }
  after { FileUtils.rm_rf(tmp) }

  def root = File.expand_path("../..", __dir__)

  def script = File.join(root, "script/release-kit")

  def canonical_workflow = File.read(File.join(root, ".github/workflows/release.yml"))

  def frozen_install = "        env:\n          BUNDLE_FROZEN: ${{ hashFiles('Gemfile.lock') != '' }}\n"

  def run_kit(script, *args)
    Open3.capture2e(script, *args)
  end

  def workflow_with_test_job(canonical, test_job)
    head, rest = canonical.split(/^  # ── project-specific.*\n/, 2)
    shared = rest[rest.index("  # ── shared")..]
    "#{head}  # ── project-specific ─\n#{test_job}\n#{shared}"
  end

  def write_target(path, content)
    File.write(File.join(target, path), content)
  end

  def read_target(path) = File.read(File.join(target, path))

  describe "sync" do
    it "copies bin/release (executable) and rakelib/release.rake verbatim" do
      _out, status = run_kit(script, "sync", target)

      expect(status).to be_success
      expect(read_target("bin/release")).to eq(File.read(File.join(root, "bin/release")))
      expect(File.executable?(File.join(target, "bin/release"))).to be(true)
      expect(read_target("rakelib/release.rake")).to eq(File.read(File.join(root, "rakelib/release.rake")))
    end

    it "replaces the shared parts of an adopted release.yml but keeps its own test job" do
      stale = workflow_with_test_job(canonical_workflow, custom_test_job).sub("gem build", "gem build --old")
      write_target(".github/workflows/release.yml", stale)

      run_kit(script, "sync", target)

      synced = read_target(".github/workflows/release.yml")
      expect(synced).to include("bundle exec my-own-suite")
      expect(synced).not_to include("gem build --old")
      expect(synced).to eq(workflow_with_test_job(canonical_workflow, custom_test_job))
    end

    it "writes the canonical release.yml on first adoption and says the test job needs porting" do
      write_target(".github/workflows/release.yml", "name: Old release\n")

      out, status = run_kit(script, "sync", target)

      expect(status).to be_success
      expect(read_target(".github/workflows/release.yml")).to eq(canonical_workflow)
      expect(out).to include("port this repo's test job")
    end
  end

  describe "check" do
    before do
      run_kit(script, "sync", target)
      write_target(".github/workflows/release.yml", workflow_with_test_job(canonical_workflow, custom_test_job))
    end

    it "passes a repo that matches the kit" do
      out, status = run_kit(script, "check", target)

      expect(status).to be_success
      expect(out).to include("demo: in sync")
    end

    it "fails on a drifted shared file" do
      File.write(File.join(target, "rakelib/release.rake"), "# edited locally\n", mode: "a")

      out, status = run_kit(script, "check", target)

      expect(status).not_to be_success
      expect(out).to include("rakelib/release.rake differs")
    end

    it "fails when the test job does not install frozen (the stale-lock gate)" do
      unfrozen = workflow_with_test_job(canonical_workflow, custom_test_job.sub(frozen_install, ""))
      write_target(".github/workflows/release.yml", unfrozen)

      out, status = run_kit(script, "check", target)

      expect(status).not_to be_success
      expect(out).to include("test job must install frozen")
    end
  end

  it "ships a canonical test job that installs frozen when a Gemfile.lock is committed" do
    expect(canonical_workflow).to include("BUNDLE_FROZEN: ${{ hashFiles('Gemfile.lock') != '' }}")
  end
end
