module AhoyDashboard
  module Alerts
    module Rules
      class RankRule < Rule
        private

        def pairs
          readings.rank_pairs
        end

        def compared(pair, headline:, detail:)
          finding(subject: pair.label, headline: headline, detail: detail,
                  check_id: pair.now&.id, previous_check_id: pair.before&.id)
        end
      end
    end
  end
end
