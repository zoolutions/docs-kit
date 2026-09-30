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
  task.patterns = %w[app lib spec rakelib Rakefile Gemfile docs-kit.gemspec]
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

# `rake release[X.Y.Z]` lives in rakelib/release.rake (shared across the
# zoolutions gems); `bin/release` is its interactive front door.

task default: %i[spec rubocop]
