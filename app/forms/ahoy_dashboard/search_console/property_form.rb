module AhoyDashboard
  module SearchConsole
    class PropertyForm < AhoyDashboard::Form
      attribute :property_uri, :string

      validates :property_uri, presence: { message: "Pick the property this site is verified under." }
      validate :one_of_the_choices

      def initialize(sites: [], **attributes)
        @sites = Array(sites)
        super(**attributes)
      end

      attr_reader :sites

      def choices
        sites.map(&:url)
      end

      def property_options
        sites.map { |site| [ site.domain? ? "#{site.label} (domain)" : site.label, site.url ] }
      end

      private

      def one_of_the_choices
        return if property_uri.blank? || choices.empty?
        return if choices.include?(property_uri)

        errors.add(:property_uri, "That property is not one Google says this account can read.")
      end
    end
  end
end
