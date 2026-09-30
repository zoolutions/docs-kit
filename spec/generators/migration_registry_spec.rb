# frozen_string_literal: true

require "generators/docs_kit/install/migration"
require "generators/docs_kit/install/migration_registry"

# The version-aware migration machinery is pure Ruby — no Rails boot, no
# destination root. A Migration is an ordered, versioned transform (its `to`
# version is the release that introduced it); the registry selects the ones a
# site hasn't applied yet (from the site's last-synced version, exclusive) and
# runs them in order, collecting the warnings each can't safely automate.
#
# The registry SHIPS EMPTY at 1.0.x — there is no cross-version transform to
# write yet. These specs exercise the mechanism against an injected list so the
# first real `1.x → 1.y` migration is a one-line addition, fully covered.
RSpec.describe DocsKit::Generators::MigrationRegistry do
  # A migration that records that it ran (into `log`) and returns the warnings
  # it was seeded with. `call` takes (root, generator); here both are nil — the
  # registry doesn't care what a migration does, only its `to` + return value.
  def migration(to:, log:, warnings: [])
    DocsKit::Generators::Migration.new(
      to: to,
      description: "to #{to}"
    ) do |_root, _generator|
      log << Gem::Version.new(to)
      warnings
    end
  end

  # Fixture versions stay BELOW the installed gem version (DocsKit::VERSION) so
  # the default `upto` ceiling never filters them — these specs isolate the
  # from-version gap logic. The ceiling itself is covered separately below.
  describe ".applicable" do
    subject(:registry) { described_class.new(migrations) }

    let(:log) { [] }
    let(:migrations) do
      [
        migration(to: "0.1.0", log: log),
        migration(to: "0.3.0", log: log),
        migration(to: "0.2.0", log: log)
      ]
    end

    it "returns migrations newer than the site's version, in ascending order" do
      applicable = registry.applicable("0.1.0")

      expect(applicable.map(&:to)).to eq([Gem::Version.new("0.2.0"), Gem::Version.new("0.3.0")])
    end

    it "treats the site version as exclusive (a migration AT the site version is already applied)" do
      # A site synced at 0.2.0 has already run the 0.2.0 migration.
      expect(registry.applicable("0.2.0").map(&:to)).to eq([Gem::Version.new("0.3.0")])
    end

    it "returns every migration for an unknown/earliest site (0.0.0)" do
      expect(registry.applicable("0.0.0").map(&:to))
        .to eq([Gem::Version.new("0.1.0"), Gem::Version.new("0.2.0"), Gem::Version.new("0.3.0")])
    end

    it "returns none when the site is at or ahead of the newest migration" do
      expect(registry.applicable("0.3.0")).to be_empty
      expect(registry.applicable("2.0.0")).to be_empty
    end

    # A migration can't legitimately target a version newer than the installed
    # gem (you can't have "arrived" at a release you don't have). Capping at the
    # gem version means that after --sync restamps the site to DocsKit::VERSION,
    # nothing re-runs — without this bound a mis-registered `to:` above VERSION
    # would fire on EVERY sync forever. Surfaced by the end-to-end drive.
    it "never returns a migration newer than the upto ceiling" do
      # 0.3.0 exists in the list; cap the effective ceiling at 0.2.0.
      expect(registry.applicable("0.1.0", upto: "0.2.0").map(&:to)).to eq([Gem::Version.new("0.2.0")])
    end

    it "defaults the upto ceiling to the current gem version (filters unreleased migrations)" do
      # A migration targeting a version ABOVE the installed gem can't apply — the
      # site can't have that release. With the default ceiling it's filtered out.
      future = Gem::Version.new(DocsKit::VERSION).bump.to_s # e.g. 1.1 for a 1.0.x gem
      ahead = described_class.new([migration(to: future, log: log)])

      expect(ahead.applicable("0.0.0")).to be_empty
    end
  end

  describe ".migrate!" do
    subject(:registry) { described_class.new(migrations) }

    let(:log) { [] }
    let(:migrations) do
      [
        migration(to: "0.1.0", log: log, warnings: ["rename c.foo → c.bar"]),
        migration(to: "0.2.0", log: log, warnings: []),
        migration(to: "0.3.0", log: log, warnings: ["delete old_route"])
      ]
    end

    it "runs only the applicable migrations, in ascending order" do
      registry.migrate!("0.1.0", nil, nil)

      expect(log).to eq([Gem::Version.new("0.2.0"), Gem::Version.new("0.3.0")])
    end

    it "collects the warnings each migration couldn't safely automate" do
      warnings = registry.migrate!("0.1.0", nil, nil)

      expect(warnings).to eq(["delete old_route"])
    end

    it "collects warnings across every applied migration (from an earliest site)" do
      warnings = registry.migrate!("0.0.0", nil, nil)

      expect(warnings).to contain_exactly("rename c.foo → c.bar", "delete old_route")
    end

    it "runs nothing and warns nothing when the site is current" do
      expect(registry.migrate!("0.3.0", nil, nil)).to eq([])
      expect(log).to be_empty
    end
  end

  # The registry the generator actually uses: one entry per release that changes
  # what a site must carry. This guards that .default is a real registry (so
  # wiring can call it) and that every registered migration can actually run
  # against the installed gem.
  describe ".default" do
    it "is a MigrationRegistry" do
      expect(described_class.default).to be_a(described_class)
    end

    it "registers the 1.2.0 migration for a site synced at 1.1" do
      targets = described_class.default.applicable("1.1.1").map(&:to)

      expect(targets).to include(Gem::Version.new("1.2.0"))
    end

    it "registers no migration newer than the installed gem" do
      unreleased = described_class::MIGRATIONS.map(&:to).select { |to| to > Gem::Version.new(DocsKit::VERSION) }

      expect(unreleased).to be_empty
    end
  end
end
