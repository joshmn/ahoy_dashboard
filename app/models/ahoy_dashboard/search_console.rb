module AhoyDashboard
  # Everything about talking to Google Search Console that is a constant or a
  # question about configuration. The services under this namespace do the work.
  module SearchConsole
    class Error < StandardError; end

    class AuthError < Error
      attr_reader :code

      def initialize(message = nil, code: nil)
        @code = code
        super(message)
      end

      # A revoked grant, a refresh token that expired because the Cloud project
      # is still in testing, and one evicted by Google's per-client token limit
      # all come back as a bare invalid_grant. Nothing in the response separates
      # them, so the only honest answer is to ask for a reconnect.
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

    # Query on its own, which is a different answer rather than a rollup of the
    # one above: Google withholds much less at this grain, and a keyword that
    # moves between pages stays one series.
    KEYWORD_DIMENSIONS = %w[query].freeze

    SLICE_DIMENSIONS = %w[device country].freeze

    ANONYMIZED_QUERY = "(anonymized)".freeze

    SEARCH_TYPE = "web".freeze

    # Search Console cuts its days in Pacific time, so every date this code
    # sends or asks for is a date in that zone rather than the dashboard's.
    GOOGLE_TIME_ZONE = ActiveSupport::TimeZone["America/Los_Angeles"]

    # Data lands two to three days late. Three is the first day that is not
    # still moving.
    LAG_DAYS = 3

    # Google keeps revising recent days, so a run rewrites the last week rather
    # than only fetching what it has never seen.
    REVISION_DAYS = 7

    # As far back as the API will go. Past this the days are gone for good, which
    # is the whole reason anything is stored locally.
    MAX_HISTORY = 16.months

    # How much history one backfill run takes. Three requests per day, so this is
    # around ninety requests an hour against a quota measured in thousands, and
    # it walks the full sixteen months inside a day. Ingestion fetches and
    # replaces one complete day at a time, so only that day's rows stay in memory.
    BACKFILL_DAYS = 30

    MAX_ROWS = 25_000

    DATA_STATE_FINAL = "final".freeze
    DATA_STATE_ALL = "all".freeze

    # The name the OAuth client's id and secret are stored under in
    # AhoyDashboard::Credential.
    CREDENTIAL_NAME = "google_oauth_client".freeze

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
        credential&.value(:client_id).presence
      end

      def client_secret
        credential&.value(:client_secret).presence
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

      def redirect_uri
        Preferences.read(:search_console, :redirect_uri) || default_redirect_uri
      end

      def stored_property
        value = Setting.read(STORED_PROPERTY_SETTING)

        value.is_a?(String) ? value.presence : nil
      end

      def store_property!(property_uri)
        Setting.write(STORED_PROPERTY_SETTING, property_uri)
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

      # A domain property's siteUrl is the literal string "sc-domain:example.com",
      # and it goes into the path as Google handed it over, percent encoded and
      # otherwise untouched.
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

      # The oldest day Google will still answer for. It moves forward every day,
      # so the backfill is racing it.
      def earliest_available_date(now: Time.current)
        latest_final_date(now: now) - MAX_HISTORY + 1.day
      end

      # The tail the nightly run cannot have reached yet, which is the only part
      # of the record worth asking Google about live.
      def pending_dates(now: Time.current)
        ((latest_final_date(now: now) + 1)..today(now: now)).to_a
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
