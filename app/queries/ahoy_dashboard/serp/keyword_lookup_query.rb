module AhoyDashboard
  module Serp
    class KeywordLookupQuery
      def self.call(**options)
        new(**options).call
      end

      def initialize(id: nil, text: nil, location: nil)
        @id = id
        @text = text.to_s.strip
        @location = location.to_s
      end

      def call
        return SerpKeyword.find_by(id: id) if id.present?
        return nil if text.empty?

        SerpKeyword.phrased(text).to_a.min_by { |keyword| preference(keyword) }
      end

      private

      attr_reader :id, :text, :location

      def preference(keyword)
        [
          keyword.query == text ? 0 : 1,
          keyword.locations.include?(location) ? 0 : 1,
          keyword.device == Serp::DEFAULT_DEVICE ? 0 : 1,
          keyword.language == Serp::DEFAULT_LANGUAGE ? 0 : 1,
          keyword.id
        ]
      end
    end
  end
end
