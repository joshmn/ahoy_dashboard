module AhoyDashboard
  # The one string Google compares character for character, worked out three ways
  # so a mismatch is visible on the screen rather than discovered as
  # redirect_uri_mismatch after the round trip.
  #
  # Three sources, in the order the gem resolves them: an override saved on the
  # Search Console screen, then the canonical host, then the host. What
  # the page adds is the fourth: the URL the browser you are reading this in
  # would produce. When those two disagree the connect button is already broken,
  # and the generator's example.com placeholder is the usual reason.
  class SearchConsoleCallbackQuery
    # The generator's own default, and nothing else. A host of localhost is a
    # real answer in development and calling it a placeholder would be wrong.
    PLACEHOLDER_HOSTS = %w[example.com www.example.com].freeze

    Callback = Data.define(:effective, :source, :browsing, :configured_host, :browsing_host) do
      def overridden?
        source == :override
      end

      # Nothing to compare against outside a request, so silence rather than a
      # warning nobody can act on.
      def comparable?
        browsing.present? && effective.present?
      end

      def matches?
        !comparable? || effective == browsing
      end

      def differs?
        !matches?
      end

      # The one mismatch nobody spots by eye. Google compares the scheme too, so
      # http against https is a refusal, and the two strings look identical in a
      # sentence unless the page says which part moved.
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

      # A placeholder host is only a problem for the host it is standing in for.
      # Reading the dashboard on localhost while config names the real domain is
      # correct and must not be flagged.
      def wrong?
        missing_host? || placeholder?
      end

      def source_label
        case source
        when :override then "the redirect URL saved on this screen"
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
                   configured_host: configured_host, browsing_host: @request&.host_with_port)
    end

    private

    attr_reader :request

    def configured_host
      AhoyDashboard.canonical_host
    end

    def source
      return :override if Preferences.read(:search_console, :redirect_uri).present?
      return :canonical_host if Preferences.read(:site, :canonical_host).present?
      return :host if AhoyDashboard.host.present?

      :none
    end

    # Built from the request rather than from config, so it is literally the
    # origin this page was served from.
    def browsing
      return nil if request.nil?

      Engine.routes.url_helpers.settings_google_callback_url(
        host: request.host_with_port, protocol: request.protocol
      )
    rescue StandardError
      nil
    end
  end
end
