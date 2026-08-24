# frozen_string_literal: true

require "json"
require "pathname"

module DocsKit
  # Reads a committed Markdown snapshot of one documentation version back as the
  # registry duck type the rest of the kit already speaks (#all / #from_slug /
  # #nav_items), so an archived version renders through TODAY's chrome — only
  # the content is frozen.
  #
  # A snapshot lives at <config.snapshots_path>/<version id>/: a manifest.json
  # describing the nav structure (see the schema in the snapshot task) plus one
  # .md file per page, written by the host-run `bin/rails docs_kit:snapshot[id]`
  # task at release time.
  #
  # A missing directory or unreadable manifest degrades to an EMPTY snapshot
  # (no pages) — a version configured before its snapshot is written must never
  # take the site down. The install generator's --sync report warns about the
  # drift instead.
  class Snapshot
    # The manifest format this reader understands; the writer stamps it so a
    # future format change is detectable rather than silently misread.
    SCHEMA = 1

    class << self
      # The snapshot for this version, memoized per [version id, directory] and
      # invalidated when manifest.json's mtime changes — the same
      # reload-on-change posture as Configuration#openapi_document, so editing
      # a snapshot in development is picked up without a server restart.
      def for(version, config: DocsKit.configuration)
        version = DocVersion.from(version)
        root = root_for(version, config)
        mtime = manifest_mtime(root)
        key = [version.id.to_s, root.to_s]

        @cache ||= {}
        cached = @cache[key]
        return cached.fetch(:snapshot) if cached && cached.fetch(:mtime) == mtime

        new(version: version, root: root).tap do |snapshot|
          @cache[key] = { snapshot: snapshot, mtime: mtime }
        end
      end

      def reset_cache!
        @cache = {}
      end

      private

      # <snapshots_path>/<id>, or nil when no snapshots path resolves (no
      # config, no Rails) — which reads back as an empty snapshot.
      def root_for(version, config)
        base = config.snapshots_path
        return if base.nil?

        Pathname.new(base).join(version.id.to_s)
      end

      def manifest_mtime(root)
        return if root.nil?

        path = root.join("manifest.json")
        path.file? ? path.mtime : nil
      rescue StandardError
        nil
      end
    end

    attr_reader :version, :root

    def initialize(version:, root:)
      @version = version
      @root = root
      @manifest = read_manifest
    end

    # Every snapshot page across the manifest's registries, in manifest order —
    # each a Snapshot::Entry quacking like a Registry::Entry.
    def all
      registries.flat_map { |registry| registry.fetch(:entries) }
    end

    def from_slug(slug)
      all.find { |entry| entry.slug.to_s == slug.to_s }
    end

    # { group => [NavItem] }, the Registry.nav_items shape — hrefs already carry
    # the version prefix, so the Sidebar's strict path == href active-matching
    # works unchanged.
    def nav_items
      nav_items_for(all)
    end

    # { heading => { group => [NavItem] } }, the Configuration#nav_groups shape,
    # from the manifest's per-registry headings — a heading with no pages is
    # dropped so the sidebar never shows an empty group.
    def nav_groups
      registries.each_with_object({}) do |registry, acc|
        items = nav_items_for(registry.fetch(:entries))
        acc[registry.fetch(:heading)] = items unless items.empty?
      end
    end

    # The version-prefixed docs prefix (e.g. "/1.0/docs").
    def path_prefix
      "#{version.path_prefix}/docs"
    end

    # The raw Markdown body of the page with this slug, or nil when unknown.
    def markdown_for(slug)
      from_slug(slug)&.markdown
    end

    private

    # The manifest's registries as { heading:, entries: [Snapshot::Entry] }.
    def registries
      @registries ||= Array(@manifest && @manifest["registries"]).map do |registry|
        prefix = registry["path_prefix"] || "/docs"
        {
          heading: registry["heading"],
          entries: Array(registry["pages"]).map do |attrs|
            Entry.new(attrs, version: version, root: root, registry_prefix: prefix)
          end
        }
      end
    end

    def nav_items_for(entries)
      entries.group_by(&:group).transform_values do |grouped|
        grouped.map { |entry| NavItem.new(href: entry.href, label: entry.title, icon: entry.icon) }
      end
    end

    # The parsed manifest Hash, or nil (→ empty snapshot) when the directory or
    # manifest is missing/unreadable — degrade, never raise (the site must stay
    # up with a version configured before its snapshot exists).
    def read_manifest
      return if root.nil?

      path = root.join("manifest.json")
      return unless path.file?

      JSON.parse(path.read)
    rescue JSON::ParserError, SystemCallError
      nil
    end
  end
end
