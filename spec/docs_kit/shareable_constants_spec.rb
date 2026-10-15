# frozen_string_literal: true

require "rails"
require "docs_kit/engine"
require "generators/docs_kit/install/migration"
require "generators/docs_kit/install/migration_registry"
require "generators/docs_kit/install/migrations/v1_2_0"

# Every constant docs-kit defines must be readable from a non-main Ractor, i.e.
# Ractor-shareable. `conformance-audit --strict` (.conformance.yml) walks them
# all on Ruby 4.0; these are the ones that were not, checked on every Ruby.
RSpec.describe "docs-kit's constants" do # rubocop:disable RSpec/DescribeClass
  {
    "DocsKit::ApiClient::DEFAULTS" => -> { DocsKit::ApiClient::DEFAULTS },
    "DocsKit::Configuration::DEFAULT_NAV" => -> { DocsKit::Configuration::DEFAULT_NAV },
    "DocsKit::Engine::JAVASCRIPT_PATH" => -> { DocsKit::Engine::JAVASCRIPT_PATH },
    "DocsUI::Callout::LEVELS" => -> { DocsUI::Callout::LEVELS },
    "DocsUI::Code::FORMATTER" => -> { DocsUI::Code::FORMATTER },
    "DocsKit::Generators::MigrationRegistry::MIGRATIONS" => -> { DocsKit::Generators::MigrationRegistry::MIGRATIONS },
    "DocsKit::Generators::MigrationRegistry.default" => -> { DocsKit::Generators::MigrationRegistry.default },
    "DocsKit::Generators::Migrations::V1_2_0::MIN_RUBY" => -> { DocsKit::Generators::Migrations::V1_2_0::MIN_RUBY },
    "DocsKit::Generators::Migrations::V1_2_0::PACKAGE_FLOORS" =>
      -> { DocsKit::Generators::Migrations::V1_2_0::PACKAGE_FLOORS }
  }.each do |name, constant|
    it "#{name} is Ractor-shareable" do
      expect(Ractor.shareable?(constant.call)).to be(true)
    end
  end

  it "keeps the API client templates callable" do
    request = DocsKit::ApiRequest.new(method: :get, path: "/v1/things", url: "https://api.example.com/v1/things")

    expect(DocsKit::ApiClient::DEFAULTS.fetch(:curl).render(request)).to include("curl")
  end
end
