module AhoyDashboard
  module Serp
    class KeywordForm < AhoyDashboard::Form
      include PlaceFields
      include TagFields
      include SiteFields

      DUPLICATE_MESSAGE = "That exact search is already tracked. Attach another site to the one " \
                          "you have instead of adding a second copy of the same search.".freeze

      attribute :query, :string
      attribute :frequency, :string, default: "daily"
      attribute :enabled, :boolean, default: true

      validates :query, presence: true, length: { maximum: 255 }

      include SearchFields

      def self.from_record(keyword)
        new(
          query: keyword.query, engine: keyword.engine, device: keyword.device,
          language: keyword.language, locations: keyword.locations.join("\n"), pages: keyword.pages,
          frequency: keyword.frequency, enabled: keyword.enabled,
          site_ids: keyword.keyword_targets.map { |target| target.site_id.to_s },
          tags: keyword.tags
        )
      end

      def record_attributes
        {
          query: query, engine: engine, device: device, language: language,
          locations: location_values, pages: pages, frequency: frequency, enabled: enabled,
          tags: tag_list
        }
      end

      def add_duplicate_error
        errors.add(:base, DUPLICATE_MESSAGE)
      end

      private

      def too_many_places
        "every place is another search every time this runs"
      end
    end
  end
end
