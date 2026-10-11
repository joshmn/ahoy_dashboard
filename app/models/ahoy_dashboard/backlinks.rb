module AhoyDashboard
  # The only surface in the suite that cannot be built, only bought.
  #
  # Nothing in this database says who links to us, and the Search Console API
  # does not expose its links report, so the sole route is an index somebody else
  # crawled the web to build.
  module Backlinks
    OFF_MESSAGE = "Backlinks are off. Turn them on under Settings, Features.".freeze
    NO_HOST_MESSAGE = "Set your site's host under Settings, General so backlinks know which site to look up.".freeze

    def self.enabled?
      Features.on?(:backlinks) && installed?
    end

    def self.installed?
      Installation.installed?(:backlinks)
    end

    def self.provider
      (Preferences.read(:backlinks, :provider) || Serp.provider).to_sym
    end

    def self.adapter
      Serp.adapter(provider)
    end

    def self.domain
      Serp.own_domain
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
      adapter.backlinks?
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
      stored.nil? || stored.room_for?(adapter_class.backlink_cost_units, now: now)
    rescue Serp::Error
      true
    end

    def self.refusal(domain: self.domain)
      return :disabled unless enabled?
      return :no_host if domain.blank?
      return :sample if sample?
      return :unsupported unless sells?
      return :unconfigured unless configured?

      :capped unless room?
    end

    def self.refusal_message(key)
      case key
      when :disabled then installed? ? OFF_MESSAGE : Schedule.not_installed_reason(:backlinks)
      when :no_host then NO_HOST_MESSAGE
      when :sample then "Backlinks would come from sample data. Choose a real search provider."
      when :unsupported then "Your search provider has no backlink data."
      when :unconfigured then "#{adapter_class.label} has no credentials set."
      when :capped then "The monthly ceiling is spent, so nothing was sent."
      end
    end
  end
end
