# frozen_string_literal: true

module DocsKit
  module Generators
    # One ordered, versioned upgrade step between two docs-kit releases. `to` is
    # the version the migration belongs to (the release that introduced the
    # change); the registry runs it when a site's last-synced version is BELOW
    # `to`. The block receives the site's `(destination_root, generator)` so it
    # can read/rewrite files via the generator's helpers, and returns the list
    # of manual-cleanup warnings it could NOT safely automate.
    #
    # Warn-only-safe by contract (the #24 drift pattern): a migration does what
    # it can idempotently — never a destructive rewrite of a hand-edited line —
    # and hands back strings for whatever needs a human. A `nil` return means
    # "nothing to warn about".
    class Migration
      attr_reader :description

      # Keeps `to` as a frozen String, so a migration list can be made
      # Ractor-shareable without freezing Gem::Version's process-wide cached
      # instances; #to hands back the Gem::Version.
      def initialize(to:, description:, &block)
        @to = -to.to_s
        @description = description
        @block = block
      end

      def to = Gem::Version.new(@to)

      # Run the transform against the site. Returns the (possibly empty) list of
      # manual-cleanup warnings — never nil, so callers can flat-map safely.
      def call(root, generator)
        Array(@block.call(root, generator))
      end
    end
  end
end
