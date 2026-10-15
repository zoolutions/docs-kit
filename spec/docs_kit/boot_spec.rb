# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

# A real Rails boot, in a child process (the suite keeps no Rails.application):
# the engine finalizes the configuration with no app code, in production and in
# development, and again after a code reload. The app configures docs-kit the
# way the README and the install generator do (DocsKit.configure in a
# to_prepare block), with per-request callables that close over mutable app
# state: they can never be Ractor-shareable, and the boot must not mind.
RSpec.describe "Booting a Rails app with docs-kit" do # rubocop:disable RSpec/DescribeClass
  let(:lib) { File.expand_path("../../lib", __dir__) }

  def boot(reloading:, after_boot: "")
    Dir.mktmpdir("docs-kit-boot") do |root|
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-e", script(root, reloading, after_boot))
      raise "child process failed: #{stderr}" unless status.success?

      JSON.parse(stdout.lines.last)
    end
  end

  def script(root, reloading, after_boot)
    <<~RUBY
      $LOAD_PATH.unshift #{lib.inspect}
      require "json"
      require "rails"
      require "action_controller/railtie"
      require "phlex/rails"
      require "daisy_ui"
      require "docs_kit"

      tenant = Struct.new(:name).new("Acme")
      brand = -> { tenant.name }
      configured = 0

      class DocsKitBootSpecApp < Rails::Application
        config.root = #{root.inspect}
        config.enable_reloading = #{reloading}
        config.eager_load = false
        config.logger = Logger.new(nil)
        config.secret_key_base = "docs-kit-boot-spec"
      end

      Rails.application.config.to_prepare do
        configured += 1
        DocsKit.configure do |c|
          c.brand = brand
          c.nav_storage_key = "docs-kit-boot-spec"
          c.nav = -> { { tenant.name => [] } }
          c.version_badge = -> { "v" + tenant.name.size.to_s }
          c.importmap = -> { tenant.name.downcase.to_sym }
          c.code_theme = "Rouge::Themes::Github"
        end
      end

      DocsKitBootSpecApp.initialize!
      #{after_boot}
      tenant.name = "Globex"
      config = DocsKit.configuration
      puts JSON.generate(
        configured: configured,
        finalized: config.finalized?,
        brand_kept: config.brand.equal?(brand),
        brand_shareable: defined?(Ractor) ? Ractor.shareable?(config.brand) : false,
        brand: config.brand_text,
        nav: config.nav_groups.keys,
        badge: config.version_badge_text,
        importmap: config.resolved_importmap.to_s,
        code_theme: config.code_theme_class.name # Rouge's theme name
      )
    RUBY
  end

  context "with code reloading off (production, test)" do
    subject(:booted) { boot(reloading: false) }

    it "finalizes the configuration, with no app code" do
      expect(booted).to include("configured" => 1, "finalized" => true, "code_theme" => "github")
    end

    it "keeps the host's unshareable callables as they are, still called per request" do
      expect(booted).to include("brand_kept" => true, "brand_shareable" => false, "brand" => "Globex",
                                "nav" => ["Globex"], "badge" => "v6", "importmap" => "globex")
    end
  end

  context "with code reloading on (development)" do
    it "finalizes the configuration at boot too" do
      expect(boot(reloading: true)).to include("configured" => 1, "finalized" => true)
    end

    it "finalizes it again after a reload re-runs the host's to_prepare configure" do
      booted = boot(reloading: true, after_boot: "Rails.application.reloader.reload!")

      expect(booted.fetch("configured")).to be > 1
      expect(booted).to include("finalized" => true, "brand_kept" => true, "brand" => "Globex")
    end
  end
end
