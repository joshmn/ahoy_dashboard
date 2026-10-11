module AhoyDashboard
  module Seo
    # How much the results themselves are moving, for these searches rather than
    # for the web. Every reading already stores the whole page it read, so a
    # reading against the one before it is a free measurement of churn nobody is
    # currently taking.
    #
    # This is worth more than a general volatility index because it is the
    # neighbourhood the site actually lives in. A quiet week everywhere is no
    # comfort if the twelve searches that matter here reshuffled.
    #
    # Two things are measured and they are not the same thing. Turnover is who is
    # on the page at all. Shuffle is how far the survivors moved. A page can hold
    # the same ten links and still be a different page.
    class VolatilityQuery
      DEPTH = 10

      # A link that fell off the read entirely is treated as having moved this
      # far rather than infinitely. Without a cap one disappearance from a ten
      # result read pins the day at maximum and nothing else can be seen.
      DROP_DISTANCE = DEPTH

      TURNOVER_WEIGHT = 0.6
      SHUFFLE_WEIGHT = 0.4

      LEVELS = [
        [ 0, "Still" ], [ 12, "Normal" ], [ 25, "Choppy" ], [ 45, "Rough" ], [ 65, "Storm" ]
      ].freeze

      Comparison = Data.define(:keyword, :query, :location, :on, :turnover, :shuffle, :score,
                               :arrived, :left) do
        def any_change?
          score.positive?
        end
      end

      Point = Data.define(:on, :score, :readings)

      Result = Data.define(:range, :points, :comparisons, :depth) do
        def any?
          points.any?
        end

        def score
          points.any? ? (points.sum(&:score) / points.size).round(1) : 0.0
        end

        def current
          points.last
        end

        def peak
          points.max_by(&:score)
        end

        def level
          VolatilityQuery.level_for(score)
        end

        def busiest
          comparisons.sort_by { |row| -row.score }
        end

        def readings
          comparisons.size
        end
      end

      def self.level_for(score)
        LEVELS.reverse_each { |floor, label| return label if score >= floor }

        LEVELS.first.last
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(range:, depth: DEPTH, tag: nil)
        @range = range
        @depth = depth
        @tag = tag
      end

      def call
        pairs = comparisons
        return Result.new(range: range, points: [], comparisons: [], depth: depth) if pairs.empty?

        Result.new(range: range, points: series(pairs), comparisons: pairs, depth: depth)
      end

      private

      attr_reader :range, :depth, :tag

      def series(pairs)
        pairs.group_by(&:on).sort.map do |on, rows|
          Point.new(on: on, score: (rows.sum(&:score) / rows.size).round(1), readings: rows.size)
        end
      end

      # Consecutive readings of the same search in the same place. A search read
      # once in the range has nothing to compare against and contributes nothing
      # rather than contributing a zero, which would read as calm.
      def comparisons
        @comparisons ||= pages.flat_map do |(keyword_id, location), reads|
          keyword = keywords[keyword_id]
          next [] if keyword.nil?

          reads.sort_by(&:first).each_cons(2).map do |(_before_at, before), (after_at, after)|
            compare(keyword, location, after_at, before, after)
          end
        end
      end

      def compare(keyword, location, on, before, after)
        was = before.sort_by { |_link, position| position }.map(&:first)
        now = after.sort_by { |_link, position| position }.map(&:first)
        held = was & now
        turnover = was.empty? ? 0.0 : 1.0 - (held.size.to_f / [ was.size, now.size ].max)
        shuffle = shuffle_for(before, after, held)
        displacement = displacement_for(before, after, held)

        Comparison.new(
          keyword: keyword, query: keyword.query, location: location,
          on: on.in_time_zone(time_zone).to_date,
          turnover: turnover, shuffle: shuffle,
          score: ((turnover * TURNOVER_WEIGHT) + (displacement * SHUFFLE_WEIGHT)) * 100,
          arrived: now - was, left: was - now
        )
      end

      def displacement_for(before, after, held)
        return 0.0 if before.empty?

        moved = before.keys.sum do |link|
          held.include?(link) ? (before[link] - after[link]).abs.clamp(0, DROP_DISTANCE) : DROP_DISTANCE
        end

        (moved.to_f / before.size) / DROP_DISTANCE
      end

      # Mean movement of the links that stayed, over the furthest they could have
      # moved, so a top ten read and a top twenty read are on the same scale.
      def shuffle_for(before, after, held)
        return 0.0 if held.empty?

        moved = held.sum { |link| (before[link] - after[link]).abs.clamp(0, DROP_DISTANCE) }

        (moved.to_f / held.size) / DROP_DISTANCE
      end

      # One hash of link to position per reading, keyed by search and place.
      def pages
        @pages ||= AhoyDashboard::SerpResult.joins(:run)
          .where("ahoy_dashboard_serp_results.position <= ?", depth)
          .where(ahoy_dashboard_serp_runs: { checked_at: range })
          .where(ahoy_dashboard_serp_runs: { status: AhoyDashboard::SerpRun.statuses.values_at(:success, :partial) })
          .merge(AhoyDashboard::SerpRun.for_tag(tag))
          .group("ahoy_dashboard_serp_runs.keyword_id", "ahoy_dashboard_serp_runs.location",
                 "ahoy_dashboard_serp_runs.checked_at")
          .pluck(Arel.sql("ahoy_dashboard_serp_runs.keyword_id"), Arel.sql("ahoy_dashboard_serp_runs.location"),
                 Arel.sql("ahoy_dashboard_serp_runs.checked_at"),
                 Arel.sql("jsonb_object_agg(ahoy_dashboard_serp_results.link, ahoy_dashboard_serp_results.position ORDER BY ahoy_dashboard_serp_results.position)"))
          .each_with_object({}) do |(keyword_id, location, at, positions), found|
            (found[[keyword_id, location]] ||= []) << [at, positions]
          end
      end

      def keywords
        @keywords ||= AhoyDashboard::SerpKeyword.where(id: pages.keys.map(&:first).uniq).index_by(&:id)
      end

      def time_zone
        @time_zone ||= AhoyDashboard.time_zone
      end
    end
  end
end
