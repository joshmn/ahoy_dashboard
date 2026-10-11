module AhoyDashboard
  module SearchConsole
    class RedirectForm < AhoyDashboard::Form
      attribute :redirect_uri, :string

      validate :redirect_uri_readable

      def self.current
        new(redirect_uri: Preferences.read(:search_console, :redirect_uri))
      end

      def self.human_attribute_name(attribute, options = {})
        attribute.to_sym == :redirect_uri ? "Redirect URL" : super
      end

      def redirect_uri
        super().to_s.strip.presence
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
