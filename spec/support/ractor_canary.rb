# frozen_string_literal: true

# Literal docs data for spec/docs_kit/ractor_canary_spec.rb. A Ractor block
# must be capture-free, so everything it reads is a constant here or an input.
module DocsKitRactorCanary
  module Pages
    Installation = Class.new
    Configuration = Class.new
  end

  # A literal `page` registry: two authored pages, one not written yet.
  class Docs
    extend DocsKit::Registry

    path_prefix "/docs"
    view_namespace "DocsKitRactorCanary::Pages"
    page "Installation", group: "Guide"
    page "Configuration", group: "Guide", icon: "settings"
    page "Unwritten", group: "Reference"
  end

  # [title, href, Markdown twin] triples, as the search controller builds them.
  PAGES = [
    ["Installation", "/docs/installation", <<~MD],
      Add the gem and render your first page.

      ## Add the gem

      Run `bundle add docs-kit`, then the install generator.

      ## Pick a theme

      The theme switcher offers every theme the CSS build ships.
    MD
    ["Configuration", "/docs/configuration", <<~MD]
      Every per-site knob lives on DocsKit.configuration.

      ## Themes

      Set c.themes to the themes your Tailwind build generates.
    MD
  ].freeze

  # A page body rendered to HTML, the input to the Markdown twin export.
  class Page < Phlex::HTML
    def view_template
      div(id: "docs-content") do
        h2 { "Add the gem" }
        p { "Run the install generator." }
      end
    end
  end
end
