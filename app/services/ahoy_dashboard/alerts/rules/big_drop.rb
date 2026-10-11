module AhoyDashboard
  module Alerts
    module Rules
      class BigDrop < RankRule
        defines key: "big_drop", name: "Dropped several places", group: :rank,
                watches: "Any tracked search", severity: :medium, default_threshold: 5, unit: "places",
                threshold_range: 1..99,
                phrase: "a search falls by %{threshold} places or more between checks"

        def findings
          pairs.select { |pair|
            pair.was.present? && pair.position.present? && (pair.position - pair.was) >= threshold
          }.map do |pair|
            compared(pair, headline: "#{pair.keyword.query} dropped #{pair.position - pair.was} places",
                           detail: "#{pair.was} to #{pair.position} between checks.")
          end
        end
      end
    end
  end
end
