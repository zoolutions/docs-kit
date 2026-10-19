# frozen_string_literal: true

require "system_helper"

# Smoke coverage of the docs-kit chrome as a real browser renders it: the landing
# page, a hand-authored doc page (masthead + sections + highlighted code), and the
# sidebar nav marking the active link. These prove the shipped chrome renders on a
# real Rails app — the integration the gem's isolated component specs can't cover.
RSpec.describe "Docs chrome", type: :system do
  it "renders the landing page hero and the docs index" do
    visit "/"

    # The hero brand mark (c.landing.logo, an inline currentColor SVG).
    expect(page).to have_css("svg[aria-label='docs-kit']")
    expect(page).to have_css("h1", text: "Shared docs chrome for Rails")
    expect(page).to have_link("Get started", href: "/docs/overview")
    # The drawer shell + sidebar are present (daisyUI Drawer).
    expect(page).to have_css(".drawer")
  end

  it "renders a hand-authored doc page with a masthead and highlighted code" do
    visit "/docs/installation"

    expect(page).to have_css("h1", text: "Installation")
    expect(page).to have_css("section")          # DocsUI::Section
    expect(page).to have_css(".code-highlight")  # a Rouge-highlighted code block
  end

it "connects the docs-nav controller, which builds the on-this-page TOC" do
  visit "/docs/configuration"

  # docs-nav is no longer preloaded (#107): the eager loader in
  # controllers/index.js imports it, and once connected it fills the TOC.
  expect(page).to have_css("[data-docs-nav-target=toc] ul[data-docs-nav-generated] a", visible: :all)
end

  it "marks the current page's sidebar link active (server-rendered, no JS)", :desktop_only do
    visit "/docs/configuration"

    # The sidebar marks the matching link with daisyUI's menu-active (computed
    # server-side from request.path — no JavaScript).
    expect(page).to have_css("a.menu-active", text: "Configuration")
  end

  it "navigates between doc pages via the sidebar", :desktop_only do
    visit "/docs/overview"

    within("aside, .drawer-side") do
      click_link "Installation"
    end

    expect(page).to have_current_path("/docs/installation")
    expect(page).to have_css("h1", text: "Installation")
  end
end
