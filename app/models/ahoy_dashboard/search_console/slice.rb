module AhoyDashboard
  module SearchConsole
    Slice = Data.define(:device, :country)

    class Slice
      UNKNOWN = "".freeze

      DEVICES = { "desktop" => "Desktop", "mobile" => "Mobile", "tablet" => "Tablet" }.freeze

      COUNTRY_FORMAT = /\A[a-z]{3}\z/

      ALL_DEVICES = "All devices".freeze
      ALL_COUNTRIES = "All countries".freeze

      class << self
        def from_params(params)
          new(device: params[:device], country: params[:country])
        end
      end

      def initialize(device: nil, country: nil)
        device = device.to_s.strip.downcase
        country = country.to_s.strip.downcase

        super(device: (device if DEVICES.key?(device)), country: (country if country.match?(COUNTRY_FORMAT)))
      end

      def any?
        device.present? || country.present?
      end

      def apply(relation)
        relation = relation.where(device: device) if device
        relation = relation.where(country: country) if country
        relation
      end

      def visits(relation)
        relation = relation.where("lower(ahoy_visits.device_type) = ?", device) if device
        return relation unless country

        letters = Countries.alpha2(country)
        return relation.where(ahoy_visits: { country: nil }) if letters.nil?

        relation.where(ahoy_visits: { country: [ letters, AhoyDashboard::Countries::NAMES[letters] ].compact })
      end

      def to_query
        to_h.compact
      end

      def device_label
        device ? DEVICES.fetch(device) : ALL_DEVICES
      end

      def country_label
        country ? Countries.name(country) : ALL_COUNTRIES
      end

      def label
        [ (device_label if device), (country_label if country) ].compact.join(" in ")
      end

      def empty_hint
        "Nothing in this range for #{label}. Days pulled before the dashboard stored device and country " \
          "only count under All devices and All countries."
      end

      def cache_key
        [ device, country ].map(&:to_s).join("/")
      end
    end
  end
end
