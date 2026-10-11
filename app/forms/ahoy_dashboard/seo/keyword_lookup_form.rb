module AhoyDashboard
  module Seo
    class KeywordLookupForm < AhoyDashboard::Form
      LANGUAGE = /\A[a-z]{2,3}(-[a-z0-9]{2,4})?\z/i

      attribute :seed, :string
      attribute :location, :string
      attribute :country, :string
      attribute :city, :string
      attribute :language, :string

      validate :seed_given
      validate :place_readable
      validate :language_readable

      def self.from_params(params)
        new(params.permit(:seed, :location, :country, :city, :language).to_h)
      end

      def seed_value
        seed.to_s.strip
      end

      def location_value
        place.value
      end

      def language_value
        language.to_s.strip.downcase.presence || Keywords.language
      end

      def place
        @place ||= begin
          code = country.to_s.strip.downcase
          town = city.to_s.strip

          if code.present? && town.present?
            Serp::Location.city(canonical_name: town, country_code: code)
          elsif code.present?
            Serp::Location.country(code)
          else
            Serp::Location.parse(location.presence || Keywords.location)
          end
        end
      end

      def message
        errors.full_messages.first
      end

      private

      def seed_given
        errors.add(:base, "Give it a phrase to start from.") if seed_value.blank?
      end

      def place_readable
        if place.problem
          errors.add(:base, "#{place.problem.upcase_first}.")
        elsif (refused = unsearchable)
          errors.add(:base, refused)
        end
      end

      def language_readable
        return if language_value.match?(LANGUAGE)

        errors.add(:base, "#{language_value.inspect} is not a language code. Use one like en or es.")
      end

      def unsearchable
        adapter = Keywords.adapter_class
        allowed = adapter.countries
        return nil if allowed.nil? || allowed.key?(place.country_code.downcase)

        "#{Settings::Display.adapter_label(adapter)} cannot look up searches from #{place.country_name}. Pick another country."
      rescue Serp::Error
        nil
      end
    end
  end
end
