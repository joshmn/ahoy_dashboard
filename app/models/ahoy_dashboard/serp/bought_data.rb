module AhoyDashboard
  module Serp
    module BoughtData
      CAPPED_MESSAGE = "The monthly ceiling is spent, so nothing was sent.".freeze

      def enabled?
        Features.on?(feature_name) && installed?
      end

      def installed?
        Installation.installed?(feature_name)
      end

      def provider
        (Preferences.read(feature_name, :provider) || Serp.provider).to_sym
      end

      def adapter
        Serp.adapter(provider)
      end

      def adapter_class
        Serp.adapter_class(provider)
      end

      def sample?
        Serp.sample?(provider)
      end

      def record
        return nil unless installed?

        SerpProvider.for(provider)
      rescue ActiveRecord::ActiveRecordError
        nil
      end

      def configured?
        adapter_class.configured?
      rescue Serp::Error
        false
      end

      def available?
        sells? && configured?
      end

      def room?(now: Time.current)
        stored = record
        stored.nil? || stored.room_for?(cost_units, now: now)
      rescue Serp::Error
        true
      end

      def refusal_message(key)
        case key
        when :disabled then installed? ? self::OFF_MESSAGE : Schedule.not_installed_reason(feature_name)
        when :unsupported then self::UNSUPPORTED_MESSAGE
        when :unconfigured then "#{adapter_class.label} has no credentials set."
        when :capped then CAPPED_MESSAGE
        end
      end
    end
  end
end
