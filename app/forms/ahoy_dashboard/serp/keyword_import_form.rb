module AhoyDashboard
  module Serp
    class KeywordImportForm < AhoyDashboard::Form
      include PlaceFields
      include TagFields
      include SearchFields
      include SiteFields

      MAX_QUERIES = 200

      attribute :selected
      attribute :pasted, :string
      attribute :frequency, :string, default: "weekly"

      validate :there_is_something_to_import

      def queries
        (Array(selected) + pasted.to_s.split("\n"))
          .map { |value| value.to_s.strip.squeeze(" ") }
          .reject(&:blank?)
          .uniq { |value| value.downcase }
          .first(MAX_QUERIES)
      end

      def shared_attributes
        {
          engine: engine, device: device, language: language, locations: location_values,
          pages: pages, frequency: frequency, source: :search_console, tags: tag_list
        }
      end

      private

      def there_is_something_to_import
        return if queries.any?

        errors.add(:base, "Nothing was picked and nothing was pasted, so there is nothing to import.")
      end

      def too_many_places
        "every place multiplies the whole import"
      end
    end
  end
end
