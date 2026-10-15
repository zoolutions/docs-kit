# frozen_string_literal: true

module DocsKit
  # One API-example language tab: a label, a Rouge lexer, a filename (a String or
  # a `(request) -> String` proc), and a `template` — a `(DocsKit::ApiRequest) ->
  # String` callable that renders the snippet. DocsUI::RequestExample turns each
  # configured client into one DocsUI::Example tab.
  #
  #   DocsKit::ApiClient.new(
  #     label: "cURL", lexer: :curl, filename: "request.sh",
  #     template: ->(req) { "curl -X #{req.http_method} '#{req.url}'" }
  #   )
  #
  # The gem ships four generic-HTTP defaults (DEFAULTS); a site overrides or
  # extends them via DocsKit.configuration.api_clients (SDK-flavored snippets, a
  # `cli` tab, ...).
  ApiClient = Data.define(:label, :lexer, :filename, :template) do
    def initialize(label:, lexer:, template:, filename: nil)
      super
    end

    # The filename for this client's title bar: a static String, or the result of
    # calling a proc filename with the request (so it can vary by verb/path).
    def filename_for(request)
      filename.respond_to?(:call) ? filename.call(request) : filename
    end

    # Render the snippet for this client from the request struct.
    def render(request) = template.call(request)
  end

  # The four generic-HTTP clients every site starts from. Order is stable
  # (curl → javascript → ruby → python) and preserved when a site merges its own.
  # Shareable (lambdas, not Method objects, which never are), so a non-main
  # Ractor can read the defaults.
  ApiClient::DEFAULTS = DocsKit::Shareable.make(
    {
      curl: ApiClient.new(
        label: "cURL", lexer: :curl, filename: "request.sh",
        template: ->(request) { ApiTemplates.curl(request) }
      ),
      javascript: ApiClient.new(
        label: "JavaScript", lexer: :javascript, filename: "request.js",
        template: ->(request) { ApiTemplates.javascript(request) }
      ),
      ruby: ApiClient.new(
        label: "Ruby", lexer: :ruby, filename: "request.rb",
        template: ->(request) { ApiTemplates.ruby(request) }
      ),
      python: ApiClient.new(
        label: "Python", lexer: :python, filename: "request.py",
        template: ->(request) { ApiTemplates.python(request) }
      )
    }
  )
end
