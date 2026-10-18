module AhoyDashboard
  module SearchConsole
    class Error < StandardError; end

    class AuthError < Error
      attr_reader :code

      def initialize(message = nil, code: nil)
        @code = code
        super(message)
      end

      def reconnect_required?
        code == INVALID_GRANT
      end
    end

    class QuotaError < Error; end

    class PermissionError < Error; end

    SCOPE = "https://www.googleapis.com/auth/webmasters.readonly".freeze
    AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth".freeze
    TOKEN_URL = "https://oauth2.googleapis.com/token".freeze
    REVOKE_URL = "https://oauth2.googleapis.com/revoke".freeze
    SITES_URL = "https://www.googleapis.com/webmasters/v3/sites".freeze

    INVALID_GRANT = "invalid_grant".freeze

    QUERY_DIMENSIONS = %w[query page].freeze

    KEYWORD_DIMENSIONS = %w[query].freeze

    SLICE_DIMENSIONS = %w[device country].freeze

    ANONYMIZED_QUERY = "(anonymized)".freeze

    SEARCH_TYPE = "web".freeze

    GOOGLE_TIME_ZONE = ActiveSupport::TimeZone["America/Los_Angeles"]

    LAG_DAYS = 3

    REVISION_DAYS = 7

    MAX_HISTORY = 16.months

    BACKFILL_DAYS = 30

    MAX_ROWS = 25_000

    DATA_STATE_FINAL = "final".freeze

    CREDENTIAL_NAME = "google_oauth_client".freeze
    CREDENTIAL_KEYS = %i[client_id client_secret].freeze

    STORED_PROPERTY_SETTING = "search_console_property".freeze

    MISSING_CREDENTIALS_MESSAGE = "Add the OAuth client ID and secret first.".freeze
    OFF_MESSAGE = "Search Console is off. Turn it on under Settings, Features.".freeze
    NO_HOST_MESSAGE = "The dashboard has no host set, so Google would have nowhere to send you back. " \
                      "Set the host under Settings, General.".freeze

    class << self
      def credential
        Credential.for(CREDENTIAL_NAME)
      end

      def client_id
        credential&.credential(:client_id).presence
      end

      def client_secret
        credential&.credential(:client_secret).presence
      end

      def enabled?
        Features.on?(:search_console) && installed? && credentials?
      end

      def installed?
        Installation.installed?(:search_console)
      end

      def credentials?
        client_id.present? && client_secret.present?
      end

      def unavailable_reason
        return nil if enabled?
        return Schedule.not_installed_reason(:search_console) unless installed?
        return MISSING_CREDENTIALS_MESSAGE unless credentials?

        OFF_MESSAGE
      end

      def sync_refusal(account = GoogleAccount.current)
        return unavailable_reason unless enabled?
        return "Connect Google first." unless account&.connected?

        "Pick a property first." unless account.property_selected?
      end

      def redirect_uri
        Preferences.read(:search_console, :redirect_uri) || default_redirect_uri
      end

      def stored_property
        Preferences.read(:search_console, :property)
      end

      def store_property!(property_uri)
        Preferences.write(:search_console, property: property_uri)
      end

      def authorization_url(state:)
        uri = URI(AUTH_URL)
        uri.query = URI.encode_www_form(
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: SCOPE,
          access_type: "offline",
          prompt: "consent",
          include_granted_scopes: "true",
          state: state
        )
        uri.to_s
      end

      def analytics_url(property_uri)
        "#{SITES_URL}/#{ERB::Util.url_encode(property_uri)}/searchAnalytics/query"
      end

      def today(now: Time.current)
        now.in_time_zone(GOOGLE_TIME_ZONE).to_date
      end

      def latest_final_date(now: Time.current)
        today(now: now) - LAG_DAYS
      end

      def ingest_dates(now: Time.current)
        last = latest_final_date(now: now)

        ((last - (REVISION_DAYS - 1))..last).to_a
      end

      def earliest_available_date(now: Time.current)
        latest_final_date(now: now) - MAX_HISTORY + 1.day
      end

      private

      def default_redirect_uri
        host = AhoyDashboard.canonical_host
        return nil if host.blank?

        AhoyDashboard::Engine.routes.url_helpers
          .settings_google_callback_url(host: host, protocol: "https")
      end
    end
  end
end
