# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)

# Lint only the gem's own source — NOT the dogfood docs/ site. docs/ is a separate
# consuming app with its own bundle and .rubocop.yml (it `inherit_gem`s
# rubocop-rails-omakase, absent from the gem's bundle). Passing explicit paths
# stops RuboCop from discovering and loading docs/.rubocop.yml, whose gem
# inheritance can't resolve here (and crashes CI). docs/ lints itself.
RuboCop::RakeTask.new do |task|
  task.patterns = %w[app lib spec Rakefile Gemfile docs-kit.gemspec]
end

# Colored status helpers shared by the build/release tasks.
module ReleaseHelpers
  def info(msg)    = puts "\e[34m→\e[0m #{msg}"
  def success(msg) = puts "\e[32m✓\e[0m #{msg}"
  def skip(msg)    = puts "\e[33m⊘\e[0m #{msg} \e[33m(skipped)\e[0m"
  def warn(msg)    = puts "\e[33m⚠\e[0m #{msg}"
  def error(msg)   = puts "\e[31m✗\e[0m #{msg}"
  def header(msg)  = puts "\n\e[1;36m#{msg}\e[0m\n#{'─' * msg.length}"
end

desc "Build gem and verify contents"
task :build do
  sh("gem build docs-kit.gemspec --strict")
  gem_file = Dir["docs-kit-*.gem"].first
  abort "Gem file not found after build" unless gem_file

  sh("gem unpack #{gem_file} --target /tmp/gem-verify")
  puts "\n=== Gem contents ==="
  sh("find /tmp/gem-verify -type f | sort")
  sh("rm -rf /tmp/gem-verify #{gem_file}")
end

desc "Release a new version (rake release[1.2.3] or rake release[pre] or rake release[1.2.3,force])"
task :release, %i[version force] do |_t, args|
  include ReleaseHelpers

  require_relative "lib/docs_kit/version"

  new_version = args[:version]
  abort "\e[31mUsage: rake release[X.Y.Z] or rake release[X.Y.Z,force]\e[0m" unless new_version

  force = args[:force]&.to_s&.downcase == "force"

  current_branch = `git branch --show-current`.strip
  unless current_branch == "main"
    abort "\e[31mAborting: must be on main branch to release (currently on #{current_branch})\e[0m"
  end

  dirty = `git status --porcelain`.strip
  abort "\e[31mAborting: working directory is not clean.\e[0m\n#{dirty}" unless dirty.empty?

  current = DocsKit::VERSION
  prerelease = new_version.match?(/alpha|beta|rc|pre/) || new_version == "pre"

  if new_version == "pre"
    new_version = current
    prerelease = true
  end

  tag = "v#{new_version}"
  version_file = "lib/docs_kit/version.rb"

  title = "Release #{tag}"
  title += " (force)" if force
  header title
  info "Current version: #{current}"
  info "New version:     #{new_version}"
  info "Pre-release:     #{prerelease}"

  # Step 0: Force cleanup — delete existing release and tag
  if force
    header "Force cleanup"
    if system("gh release view #{tag} >/dev/null 2>&1")
      sh("gh release delete #{tag} --yes --cleanup-tag")
      success "Deleted release and remote tag #{tag}"
    else
      skip "No release #{tag} to delete"
    end

    if system("git rev-parse #{tag} >/dev/null 2>&1")
      sh("git tag -d #{tag}")
      success "Deleted local tag #{tag}"
    else
      skip "No local tag #{tag} to delete"
    end
  end

  # Step 1: Update version file
  header "Version"
  if new_version == current
    skip "Version already #{new_version}"
  else
    content = File.read(version_file)
    content.sub!(/VERSION = ".*"/, "VERSION = \"#{new_version}\"")
    File.write(version_file, content)
    success "Updated #{version_file}"
  end

  # Step 2: Refresh lockfiles and verify the gem builds cleanly. docs/ is the
  # dogfood site — refresh its lock too so `bundle install` there resolves the
  # new gem version. The root Gemfile.lock is gitignored (a gem doesn't commit
  # it); docs/Gemfile.lock is tracked (the site deploys from it) and carries the
  # docs-kit version, so it is committed with the bump in Step 3.
  header "Build verification"
  sh("bundle install --quiet")
  success "Gemfile.lock refreshed"
  if File.exist?("docs/Gemfile.lock")
    sh("cd docs && bundle install --quiet")
    success "docs/Gemfile.lock refreshed"
  end
  sh("gem build docs-kit.gemspec --strict")
  sh("rm -f docs-kit-*.gem")
  success "Gem builds cleanly"

  # Step 3: Commit version bump — version.rb plus the refreshed docs/Gemfile.lock
  # (else the docs lock lags one release behind). The root Gemfile.lock is
  # gitignored, so staging it would abort on `git add`.
  header "Git commit"
  version_changed =
    !`git diff #{version_file}`.strip.empty? || !`git diff --cached #{version_file}`.strip.empty?
  if version_changed
    sh("git add #{version_file}")
    sh("git add docs/Gemfile.lock") if File.exist?("docs/Gemfile.lock")
    sh("git commit -m 'chore: bump version to #{new_version}'")
    success "Committed version bump"
  else
    skip "No version change to commit"
  end

  # Step 4: Push to origin
  header "Git push"
  local_sha = `git rev-parse HEAD`.strip
  remote_sha = `git rev-parse origin/main 2>/dev/null`.strip
  if local_sha == remote_sha
    skip "origin/main already at #{local_sha[0..6]}"
  else
    sh("git push origin main")
    success "Pushed to origin/main"
  end

  # Step 5: Create release (the Release workflow publishes to RubyGems via OIDC
  # trusted publishing on `release: published`).
  header "Release"
  tag_exists = system("git rev-parse #{tag} >/dev/null 2>&1")
  release_exists = system("gh release view #{tag} >/dev/null 2>&1")

  if release_exists
    skip "Release #{tag} already exists (use force to re-create)"
  elsif tag_exists
    info "Tag #{tag} exists, creating release from it"
    pre_flag = prerelease ? "--prerelease" : ""
    sh("gh release create #{tag} --generate-notes #{pre_flag}".strip)
    success "Release #{tag} created from existing tag"
  else
    pre_flag = prerelease ? "--prerelease" : ""
    sh("gh release create #{tag} --generate-notes --target main #{pre_flag}".strip)
    success "Release #{tag} created"
  end

  puts ""
  success "\e[1mRelease #{tag} complete!\e[0m CI will handle the rest:"
  puts "    • Run tests"
  puts "    • Build + verify gem"
  puts "    • Sign with Sigstore"
  puts "    • Publish to RubyGems (trusted publishing)"
  puts "    • Upload assets to the release"
end

task default: %i[spec rubocop]
