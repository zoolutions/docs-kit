# frozen_string_literal: true

module DocsKit
  module Generators
    module Migrations
      # The 1.1 → 1.2 upgrade. docs-kit 1.2 needs Ruby >= 3.3, scaffolds Bun 1.4.2
      # and newer Tailwind/daisyUI floors, and its reusable deploy workflow moved to
      # Node 24 actions (only callers that track `@main` get that).
      #
      # Warn-only-safe: a value is rewritten only when it is EXACTLY what an older
      # docs-kit generated (so it can't be a hand edit); anything else older is
      # handed back as a warning, and a newer value is left alone.
      module V1_2_0 # rubocop:disable Naming/ClassAndModuleCamelCase -- named after the release
        DESCRIPTION = "docs-kit 1.2: Ruby >= 3.3, Bun 1.4.2, Tailwind 4.3 / daisyUI 5.7 floors, Node 24 deploy"
        MIN_RUBY = Gem::Version.new("3.3")
        BUN = { from: "1.3.2", to: "1.4.2" }.freeze
        PACKAGE_FLOORS = {
          "tailwindcss" => { from: "^4.1.18", to: "^4.3.3" },
          "@tailwindcss/cli" => { from: "^4.1.18", to: "^4.3.3" },
          "daisyui" => { from: "^5.6.0", to: "^5.7.47" }
        }.freeze
        DEPLOY_CALL = %r{zoolutions/docs-kit/\.github/workflows/deploy\.yml@(\S+)}

        module_function

        # Returns the warnings it could not safely automate.
        def call(root)
          bun(root) + ruby(root) + package_floors(root) + deploy_pins(root)
        end

        def bun(root)
          edit(root, "Dockerfile") do |source, warnings|
            current = source[/^ARG BUN_VERSION=(\S+)$/, 1]
            next source unless current && older?(current, BUN[:to])
            next source.sub("ARG BUN_VERSION=#{current}", "ARG BUN_VERSION=#{BUN[:to]}") if current == BUN[:from]

            warnings << "Dockerfile: ARG BUN_VERSION=#{current} is older than the #{BUN[:to]} docs-kit now " \
                        "scaffolds; raise it (a bun.lock written by a newer Bun can fail " \
                        "`bun install --frozen-lockfile`)"
            source
          end
        end

        def ruby(root)
          {
            "Dockerfile" => read(root, "Dockerfile")&.[](/^ARG RUBY_VERSION=\S+$/),
            ".ruby-version" => read(root, ".ruby-version")&.strip
          }.filter_map do |file, value|
            next unless value && below_min_ruby?(value.delete_prefix("ARG RUBY_VERSION="))

            "#{file}: #{value} — docs-kit 1.2 requires Ruby >= #{MIN_RUBY}; move the site to 3.3 or newer"
          end
        end

        def package_floors(root)
          edit(root, "package.json") do |source, warnings|
            PACKAGE_FLOORS.reduce(source) do |json, (name, floor)|
              raise_floor(json, name, floor, warnings)
            end
          end
        end

        def raise_floor(json, name, floor, warnings)
          pair = /("#{Regexp.escape(name)}"\s*:\s*")([^"]+)(")/
          current = json[pair, 2]
          return json unless current && older?(current, floor[:to])
          if current == floor[:from]
            return json.sub(pair) { "#{Regexp.last_match(1)}#{floor[:to]}#{Regexp.last_match(3)}" }
          end

          warnings << "package.json: #{name} #{current} is below the #{floor[:to]} docs-kit now builds against"
          json
        end

        def deploy_pins(root)
          Dir[File.join(root, ".github/workflows/*.{yml,yaml}")].filter_map do |path|
            ref = File.read(path)[DEPLOY_CALL, 1]
            next if ref.nil? || ref == "main"

            "#{File.basename(path)}: calls docs-kit's deploy.yml@#{ref}; the Node 24 actions and " \
              "ubuntu-26.04 runners are on @main — move the pin forward (or track @main)"
          end
        end

        # Yields [source, warnings] for an existing file; writes back what the block returns.
        def edit(root, file)
          source = read(root, file)
          return [] unless source

          warnings = []
          updated = yield(source, warnings)
          File.write(File.join(root, file), updated) unless updated == source
          warnings
        end

        def read(root, file)
          path = File.join(root, file)
          File.exist?(path) ? File.read(path) : nil
        end

        # "^5.6.0" / "~> 4.1" / "3.2.4" / "ruby-3.2.4" → its version, or nil when it
        # isn't a plain version (a tag like "latest", a git URL, a range).
        def version_of(value)
          number = value.to_s[/\A(?:ruby-)?[\^~]?>?\s*(\d+(?:\.\d+)*)\z/, 1]
          number && Gem::Version.new(number)
        end

        def older?(current, target)
          current_version = version_of(current)
          current_version ? current_version < version_of(target) : false
        end

        def below_min_ruby?(value)
          version = version_of(value)
          version ? version < MIN_RUBY : false
        end
      end
    end
  end
end
