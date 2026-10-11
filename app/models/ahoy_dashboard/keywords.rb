module AhoyDashboard
  # Searches we do not rank on yet, which is the one question the stored data
  # genuinely cannot answer: Search Console only ever reports what we were
  # already shown for.
  #
  # Bought, and cached hard because of it. A seed is fetched once and read as
  # often as anybody likes; re-fetching is a button somebody presses rather than
  # something a page load does.
  module Keywords
    OFF_MESSAGE = "Keyword research is off. Turn it on under Settings, Features.".freeze

    def self.enabled?
      Features.on?(:keywords) && installed?
    end

    def self.installed?
      Installation.installed?(:keywords)
    end

    def self.provider
      (Preferences.read(:keywords, :provider) || Serp.provider).to_sym
    end

    def self.adapter
      Serp.adapter(provider)
    end

    def self.location
      Preferences.read(:keywords, :location)
    end

    def self.language
      Preferences.read(:keywords, :language)
    end

    def self.adapter_class
      Serp.adapter_class(provider)
    end

    def self.sample?
      provider == :fake
    end

    def self.record
      return nil unless installed?

      SerpProvider.for(provider)
    rescue ActiveRecord::ActiveRecordError
      nil
    end

    def self.sells?
      adapter.keywords?
    rescue Serp::Error
      false
    end

    def self.configured?
      adapter_class.configured?
    rescue Serp::Error
      false
    end

    def self.available?
      sells? && configured?
    end

    def self.room?(now: Time.current)
      stored = record
      stored.nil? || stored.room_for?(adapter_class.keyword_cost_units, now: now)
    rescue Serp::Error
      true
    end

    def self.refusal
      return :disabled unless enabled?
      return :unsupported unless sells?
      return :unconfigured unless configured?

      :capped unless room?
    end

    def self.refusal_message(key)
      case key
      when :disabled then installed? ? OFF_MESSAGE : Schedule.not_installed_reason(:keywords)
      when :unsupported then "Your search provider has no keyword data."
      when :unconfigured then "#{adapter_class.label} has no credentials set."
      when :capped then "The monthly ceiling is spent, so nothing was sent."
      end
    end
  end
end
