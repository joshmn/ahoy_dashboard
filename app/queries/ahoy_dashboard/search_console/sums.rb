module AhoyDashboard
  module SearchConsole
    module Sums
      CLICKS = Arel.sql("sum(clicks)").freeze
      IMPRESSIONS = Arel.sql("sum(impressions)").freeze
      WEIGHT = Arel.sql("sum(position * impressions)").freeze
      POSITION = Arel.sql("sum(position * impressions) / nullif(sum(impressions), 0)").freeze
      RANKING = Arel.sql("sum(clicks) desc, sum(impressions) desc").freeze
      ALL = [ CLICKS, IMPRESSIONS, WEIGHT ].freeze

      class << self
        def pick(relation)
          clicks, impressions, weight = relation.pick(*ALL)

          [ clicks.to_i, impressions.to_i, weight.to_f ]
        end

        def add(rows)
          [ rows.sum { |row| row[1].to_i }, rows.sum { |row| row[2].to_i }, rows.sum { |row| row[3].to_f } ]
        end

        def extent(relation)
          first, last = relation.pick(Arel.sql("min(date)"), Arel.sql("max(date)"))

          first && (first..last)
        end

        def best(relation, key:, pick:)
          relation.group(Arel.sql(key), Arel.sql(pick))
            .order(Arel.sql("#{key}, #{RANKING}, #{pick}"))
            .pluck(Arel.sql("distinct on (#{key}) #{key}"), Arel.sql(pick))
            .to_h
        end
      end
    end
  end
end
