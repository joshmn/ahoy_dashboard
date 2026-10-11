module AhoyDashboard
  module Serp
    module PlaceFields
      extend ActiveSupport::Concern

      included do
        attribute :place_countries
        attribute :place_cities

        validate :places_are_readable
      end

      def location_values
        values = place_countries.nil? ? locations.to_s.split("\n") : picked_places
        values.map(&:strip).reject(&:blank?).uniq
      end

      private

      def picked_places
        cities = Array(place_cities)

        Array(place_countries).each_with_index.map do |code, index|
          code = code.to_s.strip.downcase
          next if code.empty?

          city = cities[index].to_s.strip
          city.empty? ? code : Location.city(canonical_name: city, country_code: code).value
        end.select { |value| value }
      end

      def places_are_readable
        values = location_values
        return errors.add(:locations, "need at least one place to search from") if values.empty?

        if values.size > SerpKeyword::MAX_LOCATIONS
          return errors.add(:locations, "is more than #{SerpKeyword::MAX_LOCATIONS} places, and #{too_many_places}")
        end

        places = values.map { |value| Location.parse(value) }
        problems = places.map(&:problem).select { |value| value }
        return errors.add(:locations, problems.to_sentence) if problems.any?

        refused = unsearchable(places)
        errors.add(:locations, refused) if refused
      end

      def unsearchable(places)
        adapter = Serp.adapter_class
        allowed = adapter.countries
        return nil if allowed.nil?

        missing = places.map { |place| place.country_code.downcase }.uniq.reject { |code| allowed.key?(code) }
        return nil if missing.empty?

        names = missing.map { |code| Location.country(code).country_name }
        "#{Settings::Display.adapter_label(adapter)} cannot search from #{names.to_sentence}. " \
          "Pick another country, or choose another search provider."
      rescue Serp::Error
        nil
      end
    end
  end
end
