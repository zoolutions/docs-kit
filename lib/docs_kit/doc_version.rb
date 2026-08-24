# frozen_string_literal: true

module DocsKit
  # One documentation version a site serves. Sites declare these in config as
  # plain Hashes; #versions normalizes each into a DocVersion so the chrome and
  # the AI surfaces stay value-object-driven (like DocsKit::TopbarLink):
  #
  #   c.versions = [
  #     { id: "1.1", ref: "v1.1.0", current: true },
  #     { id: "1.0", ref: "v1.0.0" },
  #   ]
  #
  # #id is the URL segment (an archived version serves at "/#{id}/docs/...");
  # #label is the switcher text (defaults to the id); #ref is the git ref backing
  # the GitHub compare link (optional); #current marks the version serving
  # unprefixed at /docs (exactly today's URLs); #noindex defaults to the inverse
  # of #current — archived copies are noindex'd so search engines keep pointing
  # at the current docs, overridable per version with `noindex: false`.
  #
  # Named DocVersion, not Version — lib/docs_kit/version.rb already owns that
  # file slot and defines DocsKit::VERSION.
  DocVersion = Data.define(:id, :label, :ref, :current, :noindex) do
    def initialize(id:, label: nil, ref: nil, current: false, noindex: nil)
      super(
        id: id,
        label: label || id.to_s,
        ref: ref,
        current: current,
        noindex: noindex.nil? ? !current : noindex
      )
    end

    # Build a DocVersion from a Hash (symbol- OR string-keyed, so a YAML/JSON
    # config loads cleanly) or pass an existing DocVersion through unchanged.
    def self.from(version)
      return version if version.is_a?(self)

      attrs = version.to_h.transform_keys(&:to_sym)
      new(
        id: attrs[:id],
        label: attrs[:label],
        ref: attrs[:ref],
        current: attrs.fetch(:current, false),
        noindex: attrs[:noindex]
      )
    end

    def current? = !!current

    def archived? = !current?

    # The root URL segment this version contributes: "" for the current version
    # (existing sites and their SEO untouched), "/#{id}" for an archived one.
    # Stacks with the i18n locale prefix later ("/de/1.0/docs/...").
    def path_prefix
      current? ? "" : "/#{id}"
    end
  end
end
