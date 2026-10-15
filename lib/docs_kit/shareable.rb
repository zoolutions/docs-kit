# frozen_string_literal: true

module DocsKit
  # Makes a boot-time value Ractor-shareable: Ractor.make_shareable (a deep
  # freeze; a capture-free Proc becomes an isolated one) where the engine has
  # Ractors, a plain #freeze where it has none (TruffleRuby, JRuby). For
  # constants and DSL values written once at load, so a non-main Ractor can read
  # them and no thread can mutate them afterwards.
  module Shareable
    def self.make(value)
      defined?(::Ractor) && ::Ractor.respond_to?(:make_shareable) ? ::Ractor.make_shareable(value) : value.freeze
    end
  end
end
