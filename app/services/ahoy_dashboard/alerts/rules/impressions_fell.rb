module AhoyDashboard
  module Alerts
    module Rules
      class ImpressionsFell < SearchConsoleDrop
        defines key: "impressions_fell", name: "Impressions fell", group: :search_console,
                watches: "Search Console, the whole site", severity: :low, default_threshold: 30, unit: "percent",
                threshold_range: 1..100,
                phrase: "impressions over the last 7 finished days are down %{threshold}%% or more on the 7 days before"

        private

        def metric
          :impressions
        end

        def metric_word
          "impression"
        end

        def metric_label
          "impressions"
        end
      end
    end
  end
end
