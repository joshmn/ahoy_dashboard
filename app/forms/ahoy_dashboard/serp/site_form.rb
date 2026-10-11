module AhoyDashboard
  module Serp
    class SiteForm < AhoyDashboard::Form
      FIELDS = %i[name domain match_subdomains].freeze
      NEW_FIELDS = (FIELDS + %i[every_keyword]).freeze

      attribute :name, :string
      attribute :domain, :string
      attribute :match_subdomains, :boolean, default: false
      attribute :every_keyword, :boolean, default: true

      validates :name, presence: true
      validates :domain, presence: true
      validate :domain_is_readable

      def self.from_record(site)
        new(FIELDS.index_with { |field| site.public_send(field) })
      end

      def record_attributes
        { name: name.to_s.strip, domain: domain.to_s.strip, match_subdomains: match_subdomains }
      end

      private

      def domain_is_readable
        return if domain.blank? || Domain.host(domain).present?

        errors.add(:domain, "does not read as a domain")
      end
    end
  end
end
