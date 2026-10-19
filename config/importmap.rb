# frozen_string_literal: true

# Auto-pins the gem's bundled Stimulus controller (docs-nav) for importmap-rails
# consumers. With the defaults it is `docs_kit/controllers/docs_nav_controller`,
# preloaded nowhere. Two engine options, set in the host's config/application.rb,
# shape the pin:
#
#   config.docs_kit.preload = false                         # true, or an entry point ("docs")
#   config.docs_kit.controllers_under = "docs_kit/controllers"  # "controllers" rides the host's lazy loader
#
# How to register the controller in the host's controllers/index.js, and which
# loader to avoid: README → "Registering the controller".
docs_kit = DocsKit::Engine.config.docs_kit
pin_all_from DocsKit::Engine.root.join("app/javascript/docs_kit/controllers"),
             under: docs_kit.controllers_under,
             to: "docs_kit/controllers",
             preload: docs_kit.preload
