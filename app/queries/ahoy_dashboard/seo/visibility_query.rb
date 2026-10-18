module AhoyDashboard
  module Seo
    class VisibilityQuery
      WEIGHTINGS = %i[even impressions].freeze

      Row = Data.define(:keyword, :location, :position, :ctr, :weight, :points) do
        def query
          keyword.query
        end

        def ranked?
          position.present?
        end
      end

      Point = Data.define(:on, :index, :ranked, :tracked) do
        def share
          tracked.zero? ? 0.0 : ranked.to_f / tracked
        end
      end

      Result = Data.define(:site, :range, :weighting, :points, :rows, :tracked, :ceiling, :fell_back) do
        def any?
          points.any?
        end

        def current
          points.last
        end

        def previous
          points.first
        end

        def index
          current&.index
        end

        def change
          return nil if points.size < 2 || index.nil? || previous&.index.nil?

          index - previous.index
        end

        def best
          points.max_by(&:index)
        end

        def worst
          points.min_by(&:index)
        end

        def ranked
          current&.ranked.to_i
        end

        def contributors
          rows.select(&:ranked?).sort_by { |row| -row.points }
        end

        def dead
          rows.reject(&:ranked?)
        end

        def weighted?
          weighting == :impressions && !fell_back
        end

        def fell_back?
          fell_back
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(site:, range:, weighting: :even, tag: nil)
        @site = site
        @range = range
        @tag = tag
        @weighting = WEIGHTINGS.include?(weighting.to_s.to_sym) ? weighting.to_s.to_sym : :even
      end

      def call
        return empty if site.nil?

        readings = daily
        return empty if readings.empty?

        Result.new(site: site, range: range, weighting: weighting, points: series(readings),
                   rows: rows(readings), tracked: tracked.size, ceiling: ceiling,
                   fell_back: fell_back?)
      end

      private

      attr_reader :site, :range, :weighting, :tag

      def empty
        Result.new(site: site, range: range, weighting: weighting, points: [], rows: [],
                   tracked: 0, ceiling: 0.0, fell_back: false)
      end

      def daily
        day = AhoyDashboard::Sql::Buckets.sql("ahoy_dashboard_serp_checks.checked_at", :day)

        @daily ||= AhoyDashboard::SerpCheck.success.where(site_id: site.id)
          .in_range(range)
          .for_tag(tag)
          .at_current_places
          .order(Arel.sql("keyword_id, location, #{day}, checked_at desc, id desc"))
          .pluck(Arel.sql("distinct on (keyword_id, location, #{day}) keyword_id"), :location, day, :checked_at, :position)
      end

      def tracked
        @tracked ||= daily.map { |keyword_id, location| [ keyword_id, location ] }.uniq
      end

      def keywords
        @keywords ||= AhoyDashboard::SerpKeyword.where(id: tracked.map(&:first).uniq).index_by(&:id)
      end

      def weights
        @weights ||= (weighting == :impressions && impression_weights) || Hash.new(1.0)
      end

      def impression_weights
        return unless AhoyDashboard::SearchConsole.installed?

        totals = AhoyDashboard::SearchConsoleKeyword
          .in_range(range)
          .where(query: keywords.values.map(&:query))
          .group(:query)
          .sum(:impressions)

        mapped = keywords.transform_values { |keyword| totals[keyword.query].to_f }

        mapped.values.sum.positive? ? mapped : nil
      end

      def fell_back?
        weighting == :impressions && weights.default == 1.0
      end

      def weight_for(keyword_id)
        weights[keyword_id].to_f
      end

      def ceiling
        @ceiling ||= tracked.sum { |keyword_id, _location| weight_for(keyword_id) } * CtrCurve.best
      end

      def series(readings)
        readings.group_by { |reading| reading[2] }.sort.map do |on, day|
          earned = day.sum { |keyword_id, _location, _on, _at, position| weight_for(keyword_id) * CtrCurve.at(position) }

          Point.new(on: on, index: index_for(earned), ranked: day.count { |reading| reading[4] },
                    tracked: tracked.size)
        end
      end

      def index_for(earned)
        ceiling.zero? ? 0.0 : (earned / ceiling * 100).round(2)
      end

      def rows(readings)
        latest = readings.group_by { |keyword_id, location| [ keyword_id, location ] }
          .transform_values { |day| day.max_by { |reading| reading[3] }.last }

        tracked.map do |keyword_id, location|
          position = latest[[ keyword_id, location ]]
          weight = weight_for(keyword_id)
          ctr = CtrCurve.at(position)

          Row.new(keyword: keywords[keyword_id], location: location, position: position, ctr: ctr, weight: weight,
                  points: index_for(weight * ctr))
        end
      end
    end
  end
end
