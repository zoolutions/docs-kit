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
  # cannot read it, so it keeps its own values in Ractor-local storage instead
  # (not locked: one Ractor's threads may race to build a value, as with any `||=`).
  module Store
    # The main-only fallback, created at load and guarded by @fallback_lock.
    @fallback_lock = Mutex.new
    @fallback_values = {}

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
      def ractor_local(key)
        (::Ractor.current[:"docs_kit_store/#{key}"] ||= [yield]).first
      end

      public

      def native?
        defined?(::Ractor) ? ::Ractor.respond_to?(:store_if_absent) : false
      end
    end
  end
end
