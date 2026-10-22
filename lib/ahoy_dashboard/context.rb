# frozen_string_literal: true

module AhoyDashboard
  module Context
    class Missing < StandardError; end

    class << self
      def current
        provider = adapter
        return unless provider

        provider.current.presence || raise(Missing, "No dashboard site context is active")
      end

      def with(identifier)
        provider = adapter
        if provider.nil?
          raise Missing, "Dashboard context is no longer configured" if identifier.present?

          return yield
        end

        raise Missing, "No dashboard site context was supplied" if identifier.blank?

        begin
          Current.reset
          provider.with(identifier) { yield }
        ensure
          Current.reset
        end
      end

      private

      def adapter
        name = AhoyDashboard.config.context
        name.constantize if name
      end
    end
  end
end
