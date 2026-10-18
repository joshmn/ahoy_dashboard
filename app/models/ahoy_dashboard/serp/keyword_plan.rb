module AhoyDashboard
  module Serp
    KeywordPlan = Data.define(:pages, :place_count, :frequency) do
      def per_check(adapter_class)
        adapter_class.cost_units(pages: pages) * place_count
      end

      def monthly_units(adapter_class)
        (per_check(adapter_class) * runs_per_month).ceil
      end

      def monthly_checks
        (place_count * pages.to_i * runs_per_month).ceil
      end

      private

      def runs_per_month
        SerpKeyword::MONTH.to_f / SerpKeyword::DURATIONS.fetch(frequency).to_i
      end
    end
  end
end
