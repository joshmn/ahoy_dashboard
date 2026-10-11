module AhoyDashboard
  class Configuration
    # Who is allowed in. There is no default: without one the dashboard refuses
    # every request, because a default that let anybody in would be a data leak
    # the first time somebody forgot this file existed.
    attr_accessor :authorize

    # Whether anybody is signed in at all, so a refusal can tell "sign in" from
    # "not you". Defaults to assuming yes, which turns every refusal into a 404
    # rather than an open redirect loop.
    attr_accessor :signed_in

    # Where an unauthenticated visitor is sent. A string or something that
    # responds to call with the controller.
    attr_accessor :sign_in_path

    attr_accessor :error_screens

    # Resolved lazily so a host with its own ahoy model names can say so.
    attr_accessor :visit_model, :event_model

    # Where the dashboard's own front end is read from. Nil means the engine's
    # own copy, which is what every host wants.
    attr_accessor :assets_root

    # Where each alert goes the moment it fires. Nil means nowhere, and nowhere is
    # the default. The event is written to the feed either way, so the dashboard
    # has the record whether or not anything is delivered.
    #
    # Set it to something that responds to call with the AlertEvent. The emails
    # are set up under Settings, Emails, which is separate from this.
    attr_accessor :alert_notifier

    # The mailer classes, for an app that subclasses the emails. Who gets them
    # and when is under Settings, Emails.
    attr_reader :alerts, :reports

    # A store instance or Rails cache-store configuration. Nil uses Rails.cache.
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
