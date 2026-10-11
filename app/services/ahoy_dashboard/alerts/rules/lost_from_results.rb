module AhoyDashboard
  module Alerts
    module Rules
      class LostFromResults < RankRule
        defines key: "lost_from_results", name: "Lost from the results", group: :rank,
                watches: "Any tracked search", severity: :high,
                phrase: "a search that was ranking drops out of the results we check"

        def findings
          pairs.select { |pair| pair.moved? && pair.was.present? && pair.position.nil? }.map do |pair|
            compared(pair, headline: "Lost from the results: #{pair.keyword.query}",
                           detail: "Ranked #{pair.was} on the previous check, nowhere now.")
          end
        end
      end
    end
  end
end
