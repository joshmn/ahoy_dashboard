module AhoyDashboard
  module Serp
    class Location
      CITY_PREFIX = "city".freeze
      SEPARATOR = ":".freeze
      COUNTRY_CODE = /\A[a-z]{2}\z/i

      attr_reader :value

      class << self
        def parse(value)
          value.is_a?(Location) ? value : new(value)
        end

        def country(code)
          new(code.to_s.downcase)
        end

        def country_names
          @country_names ||= AhoyDashboard::Countries::NAMES.map { |code, name| [ code.downcase, name ] }.to_h.freeze
        end

        def city(canonical_name:, country_code: Serp::DEFAULT_COUNTRY)
          new([ CITY_PREFIX, country_code.to_s.downcase, canonical_name ].join(SEPARATOR))
        end
      end

      def initialize(value = nil)
        @value = value.to_s.strip.presence || Serp::DEFAULT_COUNTRY
      end

      def city?
        value.start_with?("#{CITY_PREFIX}#{SEPARATOR}")
      end

      def country?
        !city?
      end

      def country_code
        city? ? parts.fetch(1) : value.downcase
      end

      def canonical_name
        city? ? parts[2] : nil
      end

      def country_name
        self.class.country_names.fetch(country_code.downcase, country_code.upcase)
      end

      def readable?
        problem.nil?
      end

      # What a line has to be before a provider will take it. A country is the
      # two letter code and nothing else: that is what gl wants, and it is the
      # key DataForSEO maps to a country name. Anything else used to pass, so a
      # line reading chicago was sent as a country code, came back as a search
      # from nowhere in particular, and looked like a real ranking.
      def problem
        return nil if country? && country_code.match?(COUNTRY_CODE)
        return "#{value.inspect} is not a two letter country code" if country?
        return "#{value.inspect} is missing the place after the country code" if canonical_name.blank?
        return nil if country_code.match?(COUNTRY_CODE)

        "#{value.inspect} does not name a two letter country code to search from"
      end

      def label
        return country_code.upcase if country?

        canonical_name.to_s.split(",").map(&:strip).join(", ")
      end

      def to_s
        value
      end

      def to_param
        value
      end

      def ==(other)
        other.is_a?(Location) && other.value == value
      end

      alias_method :eql?, :==

      def hash
        value.hash
      end

      private

      def parts
        @parts ||= value.split(SEPARATOR, 3)
      end
    end
  end
end
