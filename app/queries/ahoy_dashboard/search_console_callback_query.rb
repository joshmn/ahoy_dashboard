module AhoyDashboard
  class SearchConsoleCallbackQuery
    PLACEHOLDER_HOSTS = %w[example.com www.example.com].freeze

    Callback = Data.define(:effective, :source, :browsing, :configured_host) do
      def overridden?
        source == :override
      end

      def comparable?
        browsing.present? && effective.present?
      end

      def matches?
        !comparable? || effective == browsing
      end

      def differs?
        !matches?
      end

      def scheme_only?
        return false unless differs?

        strip(effective) == strip(browsing)
      end

      def strip(url)
        url.to_s.sub(%r{\Ahttps?://}, "")
      end

      def placeholder?
        PLACEHOLDER_HOSTS.include?(configured_host.to_s.downcase)
      end

      def missing_host?
        configured_host.blank?
      end

      def wrong?
        missing_host? || placeholder?
      end

      def source_label
        case source
        when :override then "the redirect URL saved on this screen"
        when :url_options then "the dashboard host configured by your app"
        when :canonical_host then "the canonical host under Settings, General"
        when :host then "the host under Settings, General"
        else "nothing set"
        end
      end
    end

    def self.call(**options)
      new(**options).call
    end

    def initialize(request: nil)
      @request = request
    end

    def call
      Callback.new(effective: SearchConsole.redirect_uri, source: source, browsing: browsing,
                   configured_host: configured_host)
    end

    private

    attr_reader :request

    def configured_host
      AhoyDashboard.url_options[:host] || AhoyDashboard.canonical_host
    end

    def source
      return :override if Preferences.read(:search_console, :redirect_uri).present?
      return :url_options if AhoyDashboard.url_options[:host].present?
      return :canonical_host if Preferences.read(:site, :canonical_host).present?
      return :host if AhoyDashboard.host.present?

      :none
    end

    def browsing
      return nil if request.nil?

      AhoyDashboard.routes.settings_google_callback_url(
        host: request.host_with_port, protocol: request.protocol
      )
    rescue StandardError
      nil
    end
  end
end
