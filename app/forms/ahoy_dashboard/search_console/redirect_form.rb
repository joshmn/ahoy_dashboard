module AhoyDashboard
  module SearchConsole
    class RedirectForm < AhoyDashboard::Form
      LABELS = { redirect_uri: "Redirect URL" }.freeze

      attribute :redirect_uri, TRIMMED

      validate :redirect_uri_readable

      def self.current
        new(redirect_uri: Preferences.read(:search_console, :redirect_uri))
      end

      def preferences
        { search_console: { redirect_uri: redirect_uri } }
      end

      private

      def redirect_uri_readable
        return if redirect_uri.nil?

        uri = URI.parse(redirect_uri)
        return if uri.is_a?(URI::HTTP) && uri.host.present? && uri.fragment.nil?

        errors.add(:redirect_uri, "#{redirect_uri.inspect} is not a full web address. Use one like https://example.com/callback")
      rescue URI::InvalidURIError
        errors.add(:redirect_uri, "#{redirect_uri.inspect} is not a full web address. Use one like https://example.com/callback")
      end
    end
  end
end
