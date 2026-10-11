# frozen_string_literal: true

module AhoyDashboard

  module Compatibility

    class NormalizedType < SimpleDelegator
      def initialize(type:, normalizer:, normalize_nil:)
        @normalizer = normalizer
        @normalize_nil = normalize_nil
        super(type)
      end

      def cast(value)
        result = super(value)
        return result if result.nil? && !normalize_nil

        normalizer.call(result)
      end

      def serialize(value)
        super(cast(value))
      end

      private

      attr_reader :normalizer, :normalize_nil
    end
  end
end
