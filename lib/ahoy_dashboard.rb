# Nothing but Rails and csv. ahoy_matey is deliberately not a dependency either:
# Ahoy::Visit and Ahoy::Event are generated into the host application rather
# than defined by that gem, and nothing here calls ahoy itself. What this needs
# is two tables of the right shape and models over them, whatever is writing
# them and whatever they are called.

require "csv"
require "delegate"
require "digest"
require "securerandom"
require "active_record"
require "ahoy_dashboard/value"

module AhoyDashboard
  Data = Value
end

require "ahoy_dashboard/compatibility/class_names"
require "ahoy_dashboard/compatibility/normalized_type"
require "ahoy_dashboard/compatibility/enum_type"
require "ahoy_dashboard/compatibility/upsert"
require "ahoy_dashboard/compatibility/record"
require "ahoy_dashboard/version"
require "ahoy_dashboard/configuration"
require "ahoy_dashboard/markdown"
require "ahoy_dashboard/llm"
require "ahoy_dashboard/engine"
require "ahoy_dashboard/assets"
require "ahoy_dashboard/compact_number"
require "ahoy_dashboard/event_statistics"
require "ahoy_dashboard/analytics_cache"

module AhoyDashboard
  PAGE_VIEW = "page_view".freeze

  # Fired by the engagement script when a page is left or navigated away from,
  # carrying how far down it was read and how long it was open. One per page
  # view at most.
  ENGAGEMENT = "engagement".freeze

  # Fired as each quarter of a page is crossed, so a long guide can say where
  # people stop rather than only how far the average one got.
  SCROLL_MILESTONE = "scroll_milestone".freeze

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield(config)
    end

    def cache
      config.cache_store || Rails.cache
    end

    # Every range, bucket and label is read in one zone rather than UTC, because
    # a visit at 11pm belongs to the day the person had, not the day Postgres
    # had.
    def time_zone
      ActiveSupport::TimeZone[Preferences.read(:site, :time_zone).to_s] || ActiveSupport::TimeZone["UTC"]
    end

    def visit
      config.visit_model.constantize
    end

    def event
      config.event_model.constantize
    end

    def host
      Preferences.read(:site, :host)
    end

    def canonical_host
      Preferences.read(:site, :canonical_host) || host
    end

    # Sent with every request the dashboard makes on its own behalf, so the site
    # on the other end can tell who is asking.
    def user_agent
      "#{host || "ahoy_dashboard"} favicon proxy"
    end

    def authorized?(controller)
      callable = config.authorize

      return false if callable.nil?

      !!callable.call(controller)
    end

    # Where the engine is mounted in the host, so anything that has to name a
    # screen in plain text (the assistant's map of the app) says where it
    # actually lives rather than where it lived in the app this came out of.
    def mount_path(rest = nil)
      base = begin
        Rails.application.routes.url_helpers.ahoy_dashboard_path
      rescue StandardError
        "/"
      end

      return base if rest.blank?

      File.join(base, rest.to_s)
    end

    def signed_in?(controller)
      callable = config.signed_in

      callable.nil? ? true : !!callable.call(controller)
    end

    def sign_in_path(controller)
      target = config.sign_in_path

      target.respond_to?(:call) ? target.call(controller) : target
    end
  end
end
