module AhoyDashboard
  module Serp
    module SearchFields
      extend ActiveSupport::Concern

      included do
        attribute :engine, :string, default: Serp::DEFAULT_ENGINE
        attribute :device, :string, default: Serp::DEFAULT_DEVICE
        attribute :language, :string, default: Serp::DEFAULT_LANGUAGE
        attribute :locations, :string, default: Serp::DEFAULT_COUNTRY
        attribute :pages, :integer, default: 1

        validates :device, inclusion: { in: Serp::DEVICES, message: "is not one this reads" }
        validates :frequency, inclusion: { in: SerpKeyword.frequencies.keys, message: "is not a cadence" }
        validates :pages, numericality: {
          only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: Serp::MAX_PAGES
        }
      end

      def device_options
        Serp::DEVICES
      end

      def frequency_options
        SerpKeywordDecorator::FREQUENCY_LABELS.to_a
      end

      def page_options
        (1..Serp::MAX_PAGES).map { |count| [ count, "Top #{count * Serp::RESULTS_PER_PAGE}" ] }
      end
    end
  end
end
