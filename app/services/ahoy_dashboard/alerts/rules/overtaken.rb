module AhoyDashboard
  module Alerts
    module Rules
      class Overtaken < RankRule
        defines key: "overtaken", name: "Overtaken by a rival", group: :rank,
                watches: "Us against a tracked site", severity: :medium,
                phrase: "a rival moves above us on a search we were winning"

        def findings
          return [] if readings.our_site.nil?

          pairs.map do |pair|
            next if pair.position.nil? || pair.was.nil?

            rival = best_rival(pair)
            next if rival.nil? || rival.position.nil?
            next unless rival.position < pair.position && pair.was <= previous_rival_position(pair).to_i

            compared(pair, headline: "Overtaken on #{pair.keyword.query}",
                           detail: "#{rival.site.domain} is #{rival.position}, we are #{pair.position}.")
          end.select { |value| value }
        end

        private

        def best_rival(pair)
          readings.rivals[[ pair.now&.run_id, pair.location ]]&.min_by { |check| check.position || 999 }
        end

        def previous_rival_position(pair)
          readings.rivals[[ pair.before&.run_id, pair.location ]]&.map(&:position)&.select { |value| value }&.min || 999
        end
      end
    end
  end
end
