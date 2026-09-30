# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

# bin/release works out the next version from the gemspec. These run the real
# script (`list` touches nothing) inside a throwaway gem repo with a bare origin.
RSpec.describe "bin/release" do # rubocop:disable RSpec/DescribeClass -- a CLI, not a class
  let(:tmp) { Dir.mktmpdir }
  let(:repo) { File.join(tmp, "demo") }

  after { FileUtils.rm_rf(tmp) }

  def git(*args, dir:) = system("git", "-C", dir, *args, out: File::NULL, err: File::NULL, exception: true)

  def gem_repo_at(version)
    FileUtils.mkdir_p(File.join(repo, "bin"))
    FileUtils.cp(File.expand_path("../../bin/release", __dir__), File.join(repo, "bin/release"))
    File.write(File.join(repo, "demo.gemspec"), <<~RUBY)
      Gem::Specification.new do |s|
        s.name = "demo"
        s.version = "#{version}"
        s.summary = "demo"
        s.authors = ["demo"]
      end
    RUBY
    init_git_with_origin
  end

  def init_git_with_origin
    origin = File.join(tmp, "origin.git")
    git("init", "-q", "-b", "main", dir: repo)
    git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init", dir: repo)
    git("clone", "-q", "--bare", repo, origin, dir: tmp)
    git("remote", "add", "origin", origin, dir: repo)
  end

  def next_versions(version)
    gem_repo_at(version)
    out, status = Open3.capture2e(File.join(repo, "bin/release"), "list")
    raise out unless status.success?

    out.scan(/^\s+(patch|minor|major)\s+v(\S+)$/).to_h
  end

  it "bumps a stable version" do
    expect(next_versions("1.3.1")).to eq("patch" => "1.3.2", "minor" => "1.4.0", "major" => "2.0.0")
  end

  it "finalises a patch-level prerelease instead of skipping past it" do
    expect(next_versions("9.0.0.alpha1")).to eq("patch" => "9.0.0", "minor" => "9.0.0", "major" => "9.0.0")
  end

  it "finalises a prerelease only for the bumps it belongs to" do
    expect(next_versions("1.4.2.rc1")).to eq("patch" => "1.4.2", "minor" => "1.5.0", "major" => "2.0.0")
  end

  it "finalises a minor prerelease on minor, and moves on for major" do
    expect(next_versions("1.4.0.beta2")).to eq("patch" => "1.4.0", "minor" => "1.4.0", "major" => "2.0.0")
  end
end
