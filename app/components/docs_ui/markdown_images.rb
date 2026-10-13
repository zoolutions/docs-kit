# frozen_string_literal: true

module DocsUI
  # DocsUI::Markdown's image handler: `![alt](src "title")` → a lazy-loaded
  # <img>. A relative src resolves through the site's asset pipeline
  # (image_path → the digested /assets URL, Propshaft or Sprockets); an absolute,
  # protocol-relative or root-relative URL is kept as written. Off a request (an
  # isolated render) the src is used verbatim — the DocsUI::Logo posture.
  module MarkdownImages
    include Phlex::Rails::Helpers::ImagePath

    # A Markdown image sits in the prose like the kit's other bordered boxes.
    IMAGE_CLASSES = "my-4 rounded-box border border-base-300"

    # An image src kept verbatim: absolute, protocol-relative or root-relative.
    ABSOLUTE_SRC = %r{\A(?:https?:)?/}i

    # Any URL scheme. An image src may only carry http(s); a link href one of
    # LINK_SCHEMES. Scheme-less URLs (relative, root-relative, protocol-relative,
    # #anchor) always pass; javascript:, data:, vbscript: and the rest never do.
    URL_SCHEME = /\A[a-z][a-z0-9+.-]*:/i
    LINK_SCHEMES = %w[http https mailto tel].freeze

    # The descendants whose string_content makes up the alt text; a soft or hard
    # line break between them becomes a space so words don't run together.
    ALT_TEXT_NODES = %i[text code].freeze
    ALT_BREAK_NODES = %i[softbreak linebreak].freeze

    private

    # An unsafe scheme renders nothing — the alt text is dropped with it rather
    # than left behind as stray prose.
    def node_image(node)
      src = image_src(node.url)
      return unless src

      title = node.title.to_s
      img(src:, alt: alt_text(node), title: (title unless title.empty?),
          loading: "lazy", class: IMAGE_CLASSES)
    end

    # Browsers strip ASCII whitespace/control characters before reading a
    # scheme ("java\tscript:"), so the check does too.
    def image_src(url)
      bare = bare_url(url)
      return url if bare.match?(ABSOLUTE_SRC)
      return if bare.match?(URL_SCHEME)

      view_context ? image_path(url) : url
    end

    # A link's href as written, or nil when it carries a scheme outside
    # LINK_SCHEMES (the same whitespace-stripped scheme read as image_src).
    def link_href(url)
      scheme = bare_url(url)[URL_SCHEME]
      return url if scheme.nil? || LINK_SCHEMES.include?(scheme.chomp(":").downcase)

      nil
    end

    def bare_url(url) = url.to_s.gsub(/[\x00-\x20]/, "")

    # Commonmarker 2 has no plain-text export, so the alt is the image's text
    # (and inline code) descendants joined — emphasis markup is dropped.
    def alt_text(node)
      node.walk.filter_map do |n|
        if ALT_TEXT_NODES.include?(n.type) then n.string_content
        elsif ALT_BREAK_NODES.include?(n.type) then " "
        end
      end.join
    end
  end
end
