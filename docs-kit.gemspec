# frozen_string_literal: true

require_relative "lib/docs_kit/version"

Gem::Specification.new do |s|
  s.name = "docs-kit"
  s.version = DocsKit::VERSION
  s.licenses = ["MIT"]
  s.summary = "Shared Phlex docs-site chrome (shell, sidebar, code, theme switcher) built on daisyUI"
  s.description = "DocsKit is a reusable documentation-site component library for Phlex + daisyUI. " \
                  "It extracts the shared shell, sidebar, code blocks, and page kit so multiple docs " \
                  "sites look identical and are maintained in one place. Reactive demos (phlex-reactive) " \
                  "and Postgres-SSE transport (pgbus) are optional, runtime-detected add-ons."
  s.authors = ["Mikael Henriksson"]
  s.email = "mikael@zoolutions.llc"

  # Use `git ls-files` when packaging from a checkout; fall back to a Dir glob
  # when there is no .git (e.g. building a host app's Docker image from the gem
  # source copied into the container). Both paths ship the same prefixes — app/
  # carries the Phlex components, config/ carries the importmap pin.
  s.files = begin
    files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
      ls.readlines("\x0", chomp: true).select do |f|
        f.start_with?("exe/", "lib/", "app/", "config/") ||
          f == "CHANGELOG.md" || f == "LICENSE.txt" || f == "README.md"
      end
    end
    files.empty? ? raise(Errno::ENOENT) : files
  rescue Errno::ENOENT
    # lib/**/* (not just *.rb) so generator templates + USAGE + bin scripts under
    # lib/generators ship even when building without .git (e.g. in a container).
    Dir[
      "exe/*", "lib/**/*", "app/**/*", "config/**/*",
      "CHANGELOG.md", "LICENSE.txt", "README.md"
    ].select { |f| File.file?(f) }
  end

  s.bindir = "exe"
  s.executables = s.files.grep(%r{\Aexe/}) { |f| File.basename(f) }

  s.homepage = "https://github.com/zoolutions/docs-kit"
  s.metadata = {
    "source_code_uri" => "https://github.com/zoolutions/docs-kit",
    "changelog_uri" => "https://github.com/zoolutions/docs-kit/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/zoolutions/docs-kit/issues",
    "rubygems_mfa_required" => "true"
  }

  s.required_ruby_version = ">= 3.2"

  # The daisyUI Phlex component kit (Drawer/Menu/Card/...). Gemfile name is
  # `daisyui`; require path is `daisy_ui`; module is `DaisyUI`. Bounded below the
  # next major (a breaking release) so `gem build --strict` accepts it while the
  # floor stays low enough for existing hosts.
  s.add_dependency "daisyui", ">= 1.2", "< 2"
  # Phlex 2 + the Rails view glue (helper mixins, render_in, dom_id).
  s.add_dependency "phlex-rails", ">= 2.0", "< 3"
  # lucide icons synced into the host app's assets.
  s.add_dependency "rails_icons", "~> 1.1"
  # Syntax highlighting for Docs::Code. Admits rouge 5 (verified against the
  # component suite) — the `< 5` cap was silently DOWNGRADING consuming sites
  # that already ran rouge 5.x (seen in daisyui's docs app).
  s.add_dependency "rouge", ">= 4.0", "< 6"
  # GFM parsing for DocsUI::Markdown (v2 = Rust/comrak, precompiled; GFM tables +
  # strikethrough + autolink on by default). We walk its AST to Phlex nodes, so
  # commonmarker never renders HTML we'd have to html_safe.
  s.add_dependency "commonmarker", "~> 2.0"
  # HTML→Markdown export (DocsKit::MarkdownExport): we render a page, then walk
  # the HTML with a Nokogiri visitor to derive its GFM twin. Universally present
  # in Rails hosts already (loofah/rails-html-sanitizer depend on it).
  s.add_dependency "nokogiri", ">= 1.15", "< 2"
  s.add_dependency "zeitwerk", "~> 2.6"

  # phlex-reactive (reactive demos) and pgbus (Postgres-SSE transport) are
  # intentionally NOT dependencies — they are optional, runtime-detected. A site
  # that wants reactive examples adds phlex-reactive itself.

  # RuboCop is a DEVELOPMENT-time dependency: docs-kit ships custom cops under
  # lib/rubocop/cop/docs_kit/, but `require "docs_kit/rubocop"` loads rubocop
  # lazily, so it is never pulled into a host app's runtime. A consuming site
  # already has `rubocop` in its Gemfile (every generated site does) — that is
  # what runs the shipped cops. Pinned here so the gem's own cop specs can run.
  s.add_development_dependency "rubocop", ">= 1.75", "< 2"
end
