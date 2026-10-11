module AhoyDashboard
  module Serp
    class KeywordImportForm < AhoyDashboard::Form
      include PlaceFields
      include TagFields

      MAX_QUERIES = 200

      attribute :selected
      attribute :pasted, :string
      attribute :locations, :string, default: Serp::DEFAULT_COUNTRY
      attribute :pages, :integer, default: 1
      attribute :frequency, :string, default: "weekly"
      attribute :device, :string, default: Serp::DEFAULT_DEVICE
      attribute :language, :string, default: Serp::DEFAULT_LANGUAGE
      attribute :engine, :string, default: Serp::DEFAULT_ENGINE
      attribute :site_ids

      validates :device, inclusion: { in: Serp::DEVICES, message: "is not one this reads" }
      validates :frequency, inclusion: { in: SerpKeyword.frequencies.keys, message: "is not a cadence" }
      validates :pages, numericality: {
        only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: Serp::MAX_PAGES
      }
      validate :there_is_something_to_import

      def queries
        (Array(selected) + pasted.to_s.split("\n"))
          .map { |value| value.to_s.strip.squeeze(" ") }
          .reject(&:blank?)
          .uniq { |value| value.downcase }
          .first(MAX_QUERIES)
      end

      def chosen_site_ids
        Array(site_ids).reject(&:blank?).map(&:to_i)
      end

      def shared_attributes
        {
          engine: engine, device: device, language: language, locations: location_values,
          pages: pages, frequency: frequency, source: :search_console, tags: tag_list
        }
      end

      def monthly_units(adapter_class = Serp.adapter_class)
        SerpKeyword.new(shared_attributes.merge(enabled: true)).monthly_units(adapter_class) * queries.size
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
