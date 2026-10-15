# frozen_string_literal: true

# parameterize/camelize/underscore/safe_constantize for the v2 `page` DSL. A
# host Rails app already loads these; the gem requires them explicitly so the
# registry derives slugs/views even when loaded standalone (the suite, a plain
# Ruby consumer).
require "active_support/core_ext/string/inflections"

module DocsKit
  # A mixin for an in-memory docs registry (guides, demos, component references).
  #
  # Two authoring styles, one shared lookup/grouping API:
  #
  # 1. The one-line `page` DSL (v2) — the default a site should reach for. slug
  #    and view derive from the title (both overridable); instances get default
  #    readers + view_class + href for free; the sidebar nav derives from the
  #    registry with zero site code:
  #
  #      class Doc
  #        extend DocsKit::Registry
  #        path_prefix    "/docs"                 # href = "#{path_prefix}/#{slug}"
  #        view_namespace "Views::Docs::Pages"    # view_class resolves under this
  #        page "Installation",   group: "Guide"                       # slug "installation", view "Installation"
  #        page "Getting started", group: "Guide", icon: "rocket"      # slug "getting-started", view "GettingStarted"
  #        page "OAuth", group: "Guide", slug: "auth", view: "OauthGuide"  # every derivation overridable
  #      end
  #
  # 2. The low-level hash `entries` API — for a registry with a bespoke schema
  #    (custom fields, a non-default view namespace). The site writes its own
  #    initialize/readers/view_class:
  #
  #      class Demo
  #        extend DocsKit::Registry
  #        entries [{ slug: "counter", title: "Counter", group: "Examples", view: "Counter" }]
  #        attr_reader :slug, :title, :group, :view_name
  #        def initialize(entry) = (@slug, @title, @group, @view_name = entry.values_at(:slug, :title, :group, :view))
  #        def view_class = "Views::Docs::Pages::#{view_name}".safe_constantize
  #      end
  #
  #   Doc.all                                    # => [entry instances]
  #   Doc.from_slug("installation")              # => instance | nil
  #   Doc.grouped                                # => { "Guide" => [instances] }
  #   Doc.nav_items                              # => { "Guide" => [NavItem] } (authored pages only)
  #
  # A registry uses ONE style; mixing `page` and `entries` raises Registry::Error.
  module Registry
    # Raised on invalid registry declarations (e.g. mixing `page` and `entries`).
    class Error < DocsKit::Error
    end

    # Declares the frozen registry data directly (the low-level hash API). Each
    # entry is a Hash; the site supplies its own instance class behavior.
    def entries(list = nil)
      return @entries if list.nil?

      raise Error, "cannot mix `page` and `entries` in one registry" if @pages&.any?

      @entries = list.map(&:freeze).freeze
    end

    # Declares one page (the v2 DSL). slug/view derive from the title unless
    # given. Appends to the registry in declaration order (== sidebar order).
    #
    #   page "Getting started", group: "Guide", icon: "rocket", slug: "start", view: "Start"
    #
    # The DSL runs in the registry's class body, at load. Each value is made
    # Ractor-shareable on write (the page list is replaced, never appended to
    # in place), so a non-main Ractor can read a registry and no thread can
    # mutate it afterwards.
    def page(title, group:, slug: nil, view: nil, icon: nil)
      raise Error, "cannot mix `page` and `entries` in one registry" if defined?(@entries) && @entries

      entry = {
        title: title,
        group: group,
        slug: slug || title.parameterize,
        view: view || title.parameterize(separator: "_").camelize,
        icon: icon
      }
      @pages = DocsKit::Shareable.make([*(defined?(@pages) && @pages), entry])
    end

    # href = "#{path_prefix}/#{slug}". Defaults to "/docs".
    def path_prefix(value = nil)
      @path_prefix = DocsKit::Shareable.make(value) if value
      @path_prefix || "/docs"
    end

    # The namespace a page's view_class resolves under (v2 pages only), e.g.
    # "Views::Docs::Pages". Required to resolve views via the default Entry.
    def view_namespace(value = nil)
      @view_namespace = DocsKit::Shareable.make(value) if value
      @view_namespace
    end

    # The attribute used by #grouped (default :group).
    def group_by_attribute(attr = nil)
      @group_by_attribute = DocsKit::Shareable.make(attr) if attr
      @group_by_attribute || :group
    end

    # All registry instances (built fresh each call — instances are cheap and a
    # site may resolve view classes that change under code reload in development).
    # v2 pages are wrapped in the default Entry; hash entries in the site's class.
    def all
      if defined?(@pages) && @pages
        views = @view_classes || Entry::NO_VIEWS
        @pages.map { |attrs| Entry.new(attrs, path_prefix, view_namespace, views) }
      else
        (entries || []).map { |entry| new(entry) }
      end
    end

    # Resolves every `page`'s view class once (DocsKit.finalize!, at boot) into
    # a frozen { view name => class } map the entries read instead of
    # constantizing on every call. Only views that resolve are kept, so a page
    # written later still turns up. An `entries` registry resolves its own views.
    def finalize!
      resolved = Array(defined?(@pages) && @pages).each_with_object({}) do |attrs, map|
        view_class = Entry.resolve(view_namespace, attrs[:view])
        map[attrs[:view]] = view_class if view_class
      end
      @view_classes = DocsKit::Shareable.make(resolved)
      self
    end

    # Drops the resolved view classes: entries constantize again (DocsKit.configure).
    def reopen!
      @view_classes = nil
      self
    end

    # The instance whose slug matches, or nil.
    def from_slug(slug)
      all.find { |item| item.slug.to_s == slug.to_s }
    end

    # { group_value => [instances] }, preserving registry order within a group.
    def grouped
      all.group_by { |item| item.public_send(group_by_attribute) }
    end

    # { group => [NavItem] } for authored pages only (a resolvable view_class),
    # so the sidebar never links a page that isn't written yet. This is the
    # transform every site used to hand-write in its nav lambda.
    def nav_items
      all.select { |item| item.respond_to?(:view_class) && item.view_class }
         .group_by { |item| item.public_send(group_by_attribute) }
         .transform_values do |items|
        items.map { |item| DocsKit::NavItem.new(href: item.href, label: item.title, icon: item.icon) }
      end
    end

    # The default instance for a v2 `page` entry: readers + href + view_class
    # resolved under the registry's view_namespace (nil until the class exists,
    # preserving the no-dead-links behavior).
    class Entry
      NO_VIEWS = {}.freeze

      # The page class `view_name` names under `view_namespace`, or nil.
      def self.resolve(view_namespace, view_name)
        return unless view_namespace

        "#{view_namespace}::#{view_name}".safe_constantize
      end

      attr_reader :slug, :title, :group, :icon, :view_name, :href

      # view_classes: the registry's finalized { view name => class } map.
      def initialize(attrs, path_prefix, view_namespace, view_classes = NO_VIEWS)
        @slug = attrs[:slug]
        @title = attrs[:title]
        @group = attrs[:group]
        @icon = attrs[:icon]
        @view_name = attrs[:view]
        @view_namespace = view_namespace
        @view_classes = view_classes
        @href = "#{path_prefix}/#{@slug}"
      end

      # The authored Phlex page class, or nil until it's written.
      def view_class
        return unless @view_namespace

        @view_classes.fetch(@view_name) { self.class.resolve(@view_namespace, @view_name) }
      end

      # The renderable instance for this page (nil when unauthored) — the seam
      # DocsKit::Snapshot::Entry shares, so consumers render live pages and
      # snapshot pages identically (see LlmsText.renderable_for).
      def renderable
        view_class&.new
      end
    end
  end
end
