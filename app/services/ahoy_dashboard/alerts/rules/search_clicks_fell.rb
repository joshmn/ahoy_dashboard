module AhoyDashboard
  module Alerts
    module Rules
      class SearchClicksFell < SearchConsoleDrop
        defines key: "search_clicks_fell", name: "Search clicks fell", group: :search_console,
                watches: "Search Console, the whole site", severity: :medium, default_threshold: 30, unit: "percent",
                threshold_range: 1..100,
                phrase: "clicks over the last 7 finished days are down %{threshold}%% or more on the 7 days before"

        private

        def metric
          :clicks
        end

        def metric_word
          "click"
        end

        def metric_label
          "search clicks"
        end
      end
    end
  end
end
