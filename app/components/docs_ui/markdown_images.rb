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

    # Any URL scheme. Only http(s) may carry one; javascript:/data:/… are dropped.
    URL_SCHEME = /\A[a-z][a-z0-9+.-]*:/i

    # The descendants whose string_content makes up the alt text.
    ALT_TEXT_NODES = %i[text code].freeze

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
      bare = url.to_s.gsub(/[\x00-\x20]/, "")
      return url if bare.match?(ABSOLUTE_SRC)
      return if bare.match?(URL_SCHEME)

      view_context ? image_path(url) : url
    end

    # Commonmarker 2 has no plain-text export, so the alt is the image's text
    # (and inline code) descendants joined — emphasis markup is dropped.
    def alt_text(node)
      node.walk.filter_map { |n| n.string_content if ALT_TEXT_NODES.include?(n.type) }.join
    end
  end
end
