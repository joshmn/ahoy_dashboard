module AhoyDashboard
  class Configuration
    attr_accessor :authorize

    attr_accessor :signed_in

    attr_accessor :sign_in_path

    attr_accessor :error_screens

    attr_accessor :visit_model, :event_model

    attr_accessor :assets_root

    attr_accessor :alert_notifier

    attr_reader :alerts, :reports

    attr_reader :cache_store

    def cache_store=(store)
      @cache_store = store.nil? ? nil : ActiveSupport::Cache.lookup_store(store)
    end

    def initialize
      @authorize = nil
      @signed_in = ->(_controller) { true }
      @sign_in_path = "/"
      @error_screens = nil
      @visit_model = "Ahoy::Visit"
      @event_model = "Ahoy::Event"
      @assets_root = nil
      @cache_store = nil
      @alert_notifier = nil
      @alerts = ActiveSupport::OrderedOptions.new.merge!(mailer: "AhoyDashboard::AlertMailer", parent_mailer: "ActionMailer::Base")
      @reports = ActiveSupport::OrderedOptions.new.merge!(mailer: "AhoyDashboard::ReportMailer", parent_mailer: "ActionMailer::Base")
    end
  end
end
