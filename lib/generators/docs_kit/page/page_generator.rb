# frozen_string_literal: true

require "rails/generators/base"
require "active_support/core_ext/string/inflections"

module DocsKit
  module Generators
    # `rails g docs_kit:page TITLE --group=GROUP`
    #
    # Scaffolds one docs page — the Phlex page class AND its one-line registry
    # entry, both derived from the title — so adding a page is one command plus
    # writing content, not the old ceremony (a 4-level-nested class in one file
    # plus a hand-synced registry line in another, either half easy to forget).
    #
    #   rails g docs_kit:page "Getting Started" --group=Guide
    #     → app/views/docs/pages/getting_started.rb  (compact class form)
    #     → injects `page "Getting Started", group: "Guide"` into Doc
    #
    # Every derivation is overridable: --slug, --view, --eyebrow, --registry.
    # A legacy hash-`entries` registry is left untouched (an instruction is
    # printed instead of corrupting it), and re-running is idempotent.
    class PageGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      argument :title, type: :string,
                       desc: %(The page title, e.g. "Getting Started")

      class_option :group, type: :string, default: "Guide",
                           desc: "The sidebar group heading"
      class_option :slug, type: :string,
                          desc: "URL slug (default: the title parameterized)"
      class_option :view, type: :string,
                          desc: "Page class basename (default: the title camelized)"
      class_option :eyebrow, type: :string,
                             desc: "Eyebrow above the title (default: the group)"
      class_option :registry, type: :string, default: "Doc",
                              desc: "Registry class to register the page in"

      def create_page_file
        template "page.rb.erb", "app/views/docs/pages/#{view_name.underscore}.rb"
      end

      def register_page
        path = registry_path
        rel = relative(path)
        line = registry_line
        return say_status(:skip, "#{rel} not found — add `#{line}` manually", :yellow) unless File.exist?(path)

        source = File.read(path)
        return say_status(:skip, legacy_instruction(rel), :yellow) if legacy_entries?(source)
        return say_status(:identical, "#{rel} already registers #{title.inspect}", :blue) if source.include?(line)

        inject_into_file path, "  #{line}\n", after: registry_anchor(source)
      end

      private

      # The by-hand instruction printed for a legacy hash-`entries` registry the
      # generator won't touch (injecting a `page` line would corrupt it).
      def legacy_instruction(rel)
        "#{rel} uses the legacy `entries [...]` form — add this entry by hand:\n  " \
          "{ slug: #{slug.inspect}, title: #{title.inspect}, " \
          "group: #{options[:group].inspect}, view: #{view_name.inspect} }"
      end

      # The Phlex page class basename (e.g. "GettingStarted"). --view wins,
      # else camelize the title (with "_" word boundaries so hyphens don't
      # survive into the constant).
      def view_name
        options[:view].presence || title.parameterize(separator: "_").camelize
      end

      # The URL slug. --slug wins, else the title parameterized.
      def slug
        options[:slug].presence || title.parameterize
      end

      # The eyebrow above the title. --eyebrow wins, else the group.
      def eyebrow
        options[:eyebrow].presence || options[:group]
      end

      # The one-line registry entry, with only the overrides that differ from
      # the derived defaults spelled out (slug when it isn't the parameterized
      # title; view when it isn't the camelized title).
      def registry_line
        ([%(page #{title.inspect}), %(group: #{options[:group].inspect})] + override_kwargs).join(", ")
      end

      # The explicit slug:/view: keywords, present only when overridden.
      def override_kwargs
        kwargs = []
        kwargs << %(slug: #{slug.inspect}) if slug != title.parameterize
        kwargs << %(view: #{view_name.inspect}) if view_name != title.parameterize(separator: "_").camelize
        kwargs
      end

      # A registry using the v2 `page` DSL has (or will have) `page` lines. The
      # legacy form declares a hash `entries [...]` array and no `page` line.
      def legacy_entries?(source)
        source.match?(/^\s*entries\s*\[/) && !source.match?(/^\s*page\s+["']/)
      end

      # Inject after the last existing `page` line of the FILE so ordering lands
      # at the end of the last group; else after view_namespace/path_prefix;
      # else after the `extend DocsKit::Registry` line.
      #
      # The `page` anchor is the last matching line as a String, not a Regexp:
      # Thor's inject_into_file replaces EVERY match of a Regexp `after:`, so a
      # "page line not followed by a page line" pattern fires once per group in
      # a registry laid out with blank-line-separated groups (the layout
      # docs_kit:install produces) and duplicates the entry.
      def registry_anchor(source)
        case source
        when /^\s*page\s+["']/
          source.lines.grep(/^\s*page\s+["']/).last
        when /^\s*view_namespace\s/
          /^\s*view_namespace .*\n/
        when /^\s*path_prefix\s/
          /^\s*path_prefix .*\n/
        else
          /extend DocsKit::Registry\n/
        end
      end

      def registry_path
        File.join(destination_root, "app/models/#{options[:registry].underscore}.rb")
      end

      def relative(path) = path.sub("#{destination_root}/", "")
    end
  end
end
