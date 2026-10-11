module AhoyDashboard
  module Serp
    class KeywordForm < AhoyDashboard::Form
      include PlaceFields
      include TagFields

      FIELDS = %i[query engine device language locations place_countries place_cities pages frequency enabled site_ids tags].freeze
      DUPLICATE_MESSAGE = "That exact search is already tracked. Attach another site to the one " \
                          "you have instead of adding a second copy of the same search.".freeze

      attribute :query, :string
      attribute :engine, :string, default: Serp::DEFAULT_ENGINE
      attribute :device, :string, default: Serp::DEFAULT_DEVICE
      attribute :language, :string, default: Serp::DEFAULT_LANGUAGE
      attribute :locations, :string, default: Serp::DEFAULT_COUNTRY
      attribute :pages, :integer, default: 1
      attribute :frequency, :string, default: "daily"
      attribute :enabled, :boolean, default: true
      attribute :site_ids

      validates :query, presence: true, length: { maximum: 255 }
      validates :device, inclusion: { in: Serp::DEVICES, message: "is not one this reads" }
      validates :frequency, inclusion: { in: SerpKeyword.frequencies.keys, message: "is not a cadence" }
      validates :pages, numericality: {
        only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: Serp::MAX_PAGES
      }

      def self.from_record(keyword)
        new(
          query: keyword.query, engine: keyword.engine, device: keyword.device,
          language: keyword.language, locations: keyword.locations.join("\n"), pages: keyword.pages,
          frequency: keyword.frequency, enabled: keyword.enabled,
          site_ids: keyword.keyword_targets.map { |target| target.site_id.to_s },
          tags: keyword.tags
        )
      end

      def chosen_site_ids
        Array(site_ids).reject(&:blank?).map(&:to_i)
      end

      def record_attributes
        {
          query: query, engine: engine, device: device, language: language,
          locations: location_values, pages: pages, frequency: frequency, enabled: enabled,
          tags: tag_list
        }
      end

      private

      def too_many_places
        "every place is another search every time this runs"
      end
    end
  end
end
