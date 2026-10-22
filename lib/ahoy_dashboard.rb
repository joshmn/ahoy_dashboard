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
require "ahoy_dashboard/context"
require "ahoy_dashboard/scheduler"
require "ahoy_dashboard/scheduler/middleware"
require "ahoy_dashboard/markdown"
require "ahoy_dashboard/http_client"
require "ahoy_dashboard/llm"
require "ahoy_dashboard/engine"
require "ahoy_dashboard/assets"
require "ahoy_dashboard/compact_number"
require "ahoy_dashboard/date_format"
require "ahoy_dashboard/event_statistics"
require "ahoy_dashboard/analytics_cache"
require "ahoy_dashboard/search_term"
require "ahoy_dashboard/share"
require "ahoy_dashboard/counted"

module AhoyDashboard
  PAGE_VIEW = "page_view".freeze

  ENGAGEMENT = "engagement".freeze

  SCROLL_MILESTONE = "scroll_milestone".freeze

  @scheduler = Scheduler.new

  class << self
    attr_reader :scheduler

    def config
      @config ||= Configuration.new
    end

    def configure
      yield(config)
    end

    def cache
      config.cache_store || Rails.cache
    end

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

    def user_agent
      host.present? ? "ahoy_dashboard/#{VERSION} (#{host})" : "ahoy_dashboard/#{VERSION}"
    end

    def authorized?(controller)
      callable = config.authorize

      return false if callable.nil?

      !!callable.call(controller)
    end

    def allowed?(controller, permission)
      callable = config.authorize_action
      callable.nil? || !!callable.call(controller, permission)
    end

    def url_options
      callable = config.url_options
      callable ? callable.call : {}
    end

    def routes
      Routes.new
    end

    def mount_path(rest = nil)
      base = routes.root_path.chomp("/").presence || "/"

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
