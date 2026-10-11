module AhoyDashboard
  module Alerts
    module Rules
      class OverviewAppeared < RankRule
        defines key: "overview_appeared", name: "AI overview appeared", group: :rank,
                watches: "Any tracked search", severity: :medium,
                phrase: "an overview shows where the previous check had none"

        def findings
          pairs.select { |pair|
            pair.now&.ai_overview_present && pair.before.present? && !pair.before.ai_overview_present
          }.map do |pair|
            compared(pair, headline: "AI overview appeared on #{pair.keyword.query}",
                           detail: pair.now.ai_overview_cited ? "It cites us." : "It does not cite us.")
          end
        end
      end
    end
  end
end
