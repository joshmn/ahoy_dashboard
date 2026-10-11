module AhoyDashboard
  module Alerts
    module Rules
      class CitationLost < RankRule
        defines key: "citation_lost", name: "Overview stopped citing us", group: :rank,
                watches: "Any tracked search", severity: :medium,
                phrase: "the overview cited us on the last check and does not now"

        def findings
          pairs.select { |pair|
            pair.before&.ai_overview_cited && pair.now.present? && !pair.now.ai_overview_cited
          }.map do |pair|
            compared(pair, headline: "Overview stopped citing us on #{pair.keyword.query}",
                           detail: pair.now.ai_overview_present ? "The overview still shows." : "The overview is gone too.")
          end
        end
      end
    end
  end
end
