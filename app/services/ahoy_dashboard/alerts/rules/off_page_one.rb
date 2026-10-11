module AhoyDashboard
  module Alerts
    module Rules
      class OffPageOne < RankRule
        defines key: "off_page_one", name: "Fell off page one", group: :rank,
                watches: "Any tracked search", severity: :high, default_threshold: 10, unit: "position",
                threshold_range: 1..99,
                phrase: "a search moves from %{threshold} or better to worse than that"

        def findings
          pairs.select { |pair|
            pair.was.present? && pair.was <= threshold && (pair.position.nil? || pair.position > threshold)
          }.map do |pair|
            compared(pair, headline: "#{pair.keyword.query} fell to #{pair.position || "nowhere"}",
                           detail: "Was #{pair.was} on the previous check.")
          end
        end
      end
    end
  end
end
