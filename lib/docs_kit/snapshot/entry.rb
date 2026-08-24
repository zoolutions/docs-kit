# frozen_string_literal: true

module DocsKit
  class Snapshot
    # One snapshot page — the duck type of DocsKit::Registry::Entry (#slug /
    # #title / #group / #icon / #href / #view_class / #renderable), so the
    # enumeration seam (LlmsText.pages) and its consumers treat a frozen
    # Markdown page exactly like a live Ruby one. #view_class is the truthy
    # DocsUI::ArchivedPage constant, so the `select(&:view_class)` authored-page
    # filter passes unchanged.
    class Entry
      attr_reader :slug, :title, :group, :icon, :file, :digest, :href

      def initialize(attrs, version:, root:, registry_prefix:)
        @slug = attrs["slug"]
        @title = attrs["title"]
        @group = attrs["group"]
        @icon = attrs["icon"]
        @file = attrs["file"]
        @digest = attrs["digest"]
        @root = root
        @href = "#{version.path_prefix}#{registry_prefix}/#{@slug}"
      end

      # The renderer for every archived page. Truthy (never nil): a snapshot
      # page is by definition authored — its content is the committed .md file.
      def view_class
        DocsUI::ArchivedPage
      end

      # The renderable the controllers hand to Phlex — an ArchivedPage carrying
      # this entry, where a live Registry::Entry builds `view_class.new`.
      def renderable
        DocsUI::ArchivedPage.new(entry: self)
      end

      # The raw Markdown body from the snapshot file. A missing/unreadable file
      # degrades to "" — the page renders empty rather than 500ing.
      def markdown
        return "" if @root.nil? || @file.nil?

        @root.join(@file).read
      rescue SystemCallError
        ""
      end
    end
  end
end
