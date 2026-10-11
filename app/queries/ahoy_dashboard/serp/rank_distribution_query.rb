module AhoyDashboard
  module Serp
    class RankDistributionQuery
      Reading = Data.define(:at, :position)

      Day = Data.define(:date, :counts) do
        def count(key)
          counts.fetch(key, 0)
        end

        def total
          counts.values.sum
        end
      end

      Result = Data.define(:days) do
        def any?
          days.any? { |day| day.total.positive? }
        end

        def latest
          days.last
        end

        def peak
          days.map(&:total).max.to_i
        end

        def count(key)
          latest ? latest.count(key) : 0
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(site:, range:, tag: nil, now: Time.current)
        @site = site
        @range = range
        @tag = tag.presence
        @now = now.in_time_zone(zone)
      end

      def call
        return Result.new(days: []) if site.nil? || range.nil?

        series = readings
        cursors = series.keys.index_with(-1)

        Result.new(days: dates.map { |date| Day.new(date: date, counts: tally(series, cursors, cutoff(date))) })
      end

      private

      attr_reader :site, :range, :tag, :now

      def zone
        @zone ||= AhoyDashboard.time_zone
      end

      def dates
        first = range.begin.in_time_zone(zone).to_date
        last = [ range.end, now ].min.in_time_zone(zone).to_date

        first <= last ? (first..last).to_a : []
      end

      def cutoff(date)
        [ date.in_time_zone(zone).end_of_day, range.end ].min
      end

      def tally(series, cursors, cutoff)
        counts = RankBand::KEYS.index_with(0)

        series.each do |key, list|
          index = cursors.fetch(key)
          index += 1 while index + 1 < list.size && list[index + 1].at <= cutoff
          cursors[key] = index
          next if index.negative?

          counts[RankBand.for(list[index].position).key] += 1
        end

        counts
      end

      def readings
        inside = group(scope.where(checked_at: range).order(:checked_at, :id)
          .pluck(:keyword_id, :location, :checked_at, :position))
        return inside if inside.empty?

        before = group(seeds(inside.keys.map(&:first).uniq))

        inside.map { |key, list| [ key, Array(before[key]) + list ] }.to_h
      end

      def scope
        checks = SerpCheck.where(site_id: site.id, status: SerpCheck.statuses[:success]).at_current_places
        tag ? checks.where(keyword_id: SerpKeyword.tagged(tag).select(:id)) : checks
      end

      def seeds(keyword_ids)
        scope.where(keyword_id: keyword_ids).where(SerpCheck.arel_table[:checked_at].lt(range.begin))
          .order(:keyword_id, :location, checked_at: :desc, id: :desc)
          .pluck(Arel.sql("distinct on (keyword_id, location) keyword_id"), :location, :checked_at, :position)
      end

      def group(rows)
        rows.each_with_object({}) do |(keyword_id, location, at, position), grouped|
          (grouped[[ keyword_id, location ]] ||= []) << Reading.new(at: at, position: position)
        end
      end
    end
  end
end
