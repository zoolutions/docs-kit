# frozen_string_literal: true

require "rails_helper"

# The engine auto-pins docs-nav into the site's import map without a preload
# (config.docs_kit.preload defaults to false, #107): the page's import map still
# maps the module controllers/index.js eager-loads, but no
# <link rel="modulepreload"> makes every page download it up front.
RSpec.describe "The docs-nav import map pin", type: :request do
  it "maps docs-nav in the page's import map without preloading it" do
    get "/docs/overview"

    importmap = JSON.parse(response.parsed_body.at_css("script[type='importmap']").text)
    preloads = response.parsed_body.css("link[rel='modulepreload']").map { |link| link["href"] }

    expect(importmap["imports"]).to include("docs_kit/controllers/docs_nav_controller")
    expect(preloads).to be_present
    expect(preloads).not_to include(a_string_including("docs_nav_controller"))
  end
end
