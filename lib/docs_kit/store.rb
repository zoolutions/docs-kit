# frozen_string_literal: true

module DocsKit
  # Per-Ractor lazy storage for docs-kit's caches: `Store.fetch(:docs_kit_x) { {} }`.
  # A copy of conformance-kit's ConformanceKit::Store (MIT, same author): the kit
  # is a development dependency only, so the gem carries its own.
  #
  # On Ruby 3.4+ this is `Ractor.store_if_absent`, atomic and per-Ractor. Below
  # 3.4 (and on engines without Ractor) the main Ractor uses one Hash guarded by
  # a Mutex, created at load (never lazily, so there is no check-then-set race);
  # it is allowlisted main-only in .conformance.yml. A non-main Ractor on 3.3
  # cannot read it, so it keeps its own values in Ractor-local storage instead.
  # That path has no lock (none is shareable): threads of one Ractor that miss
  # together may each build a value, but only the first one stored is kept and
  # returned to all of them.
  module Store
    # rubocop:disable ThreadSafety/MutableClassInstanceVariable -- main-only fallback, guarded by @fallback_lock
    @fallback_lock = Mutex.new
    @fallback_values = {}
    # rubocop:enable ThreadSafety/MutableClassInstanceVariable

    class << self
      def fetch(key, &init)
        raise ArgumentError, "DocsKit::Store.fetch(#{key.inspect}) needs an initializer block" unless init
        return ::Ractor.store_if_absent(key, &init) if native?
        return ractor_local(key, &init) unless main_ractor?

        @fallback_lock.synchronize do
          @fallback_values.fetch(key) { @fallback_values[key] = yield }
        end
      end

      private

      def main_ractor? = !defined?(::Ractor) || ::Ractor.current == ::Ractor.main

      # Boxed, so a nil or false value is cached rather than rebuilt on every fetch.
      # The value is built before the check-then-store, which runs no Ruby code
      # between the read and the write, so a thread that built a value after
      # another stored one gets the stored one.
      def ractor_local(key)
        slot = :"docs_kit_store/#{key}"
        stored = ::Ractor.current[slot]
        return stored.first if stored

        built = [yield]
        (::Ractor.current[slot] ||= built).first
      end

      public

      def native?
        defined?(::Ractor) ? ::Ractor.respond_to?(:store_if_absent) : false
      end
    end
  end
end
