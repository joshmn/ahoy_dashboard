module AhoyDashboard
  module Seo
    # One number for the whole tracked set, so a move can be read without going
    # down a list of two hundred positions and adding them up by eye.
    #
    # The index is the share of the clicks the tracked set could have got if
    # every search in it finished first. A search sitting at eleven contributes
    # almost nothing, which is the point: counting positions treats eleventh and
    # first as one row each, and they are not one row each.
    #
    # The denominator is every search tracked in the range, not every search that
    # ranked. Otherwise falling out of the results improves the score.
    class VisibilityQuery
      WEIGHTINGS = %i[even impressions].freeze

      Row = Data.define(:keyword, :query, :location, :position, :ctr, :weight, :points) do
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

        # Asked for impressions, got none worth dividing by, so it is an even
        # weighting wearing the other one's label unless the page says otherwise.
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

      # The last reading of each search on each day it was read. Two runs in one
      # day is a re-check, not two searches, and averaging them would let a
      # morning reading hold a score down after the afternoon fixed it.
      def daily
        day = AhoyDashboard::Sql::Buckets.sql("ahoy_dashboard_serp_checks.checked_at", :day)

        @daily ||= AhoyDashboard::SerpCheck
          .where(site_id: site.id, status: AhoyDashboard::SerpCheck.statuses[:success])
          .in_range(range)
          .for_tag(tag)
          .select("distinct on (keyword_id, location, #{day}) ahoy_dashboard_serp_checks.*, #{day} as on_day")
          .order(Arel.sql("keyword_id, location, #{day}, checked_at desc, id desc"))
          .to_a
      end

      # Every search being tracked over the range, whether or not it ranked on a
      # given day. This is the denominator, and it is deliberately not the count
      # of rows on the day: a search that stopped ranking has to keep costing
      # something or falling out of the results reads as an improvement.
      def tracked
        @tracked ||= daily.map { |check| [ check.keyword_id, check.location ] }.uniq
      end

      def keywords
        @keywords ||= AhoyDashboard::SerpKeyword.where(id: tracked.map(&:first).uniq).index_by(&:id)
      end

      # What one search counts for. Even means every tracked search is worth the
      # same, which is the honest default when nothing is known about demand.
      # Impressions weights each by what Search Console says it actually got,
      # which is this site's own demand rather than a bought estimate, and is
      # right up until a search nobody has ever ranked for weighs nothing.
      def weights
        @weights ||= (weighting == :impressions && impression_weights) || Hash.new(1.0)
      end

      # Everything at zero is not a weighting, it is a blank page. Falling back to
      # even is better than reporting nothing, and #fell_back? is what lets the
      # page say which one it actually used.
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

      # The most the tracked set could score: every search first. Dividing by it
      # is what turns a sum of click shares into something between nothing and a
      # hundred.
      def ceiling
        @ceiling ||= tracked.sum { |keyword_id, _location| weight_for(keyword_id) } * CtrCurve.best
      end

      def series(readings)
        readings.group_by(&:on_day).sort.map do |on, checks|
          earned = checks.sum { |check| weight_for(check.keyword_id) * CtrCurve.at(check.position) }

          Point.new(on: on, index: index_for(earned), ranked: checks.count(&:ranked?),
                    tracked: tracked.size)
        end
      end

      def index_for(earned)
        ceiling.zero? ? 0.0 : (earned / ceiling * 100).round(2)
      end

      # What each search is putting into the number, so a score that moved can be
      # traced to the searches that moved it rather than being taken on faith.
      def rows(readings)
        latest = readings.group_by { |check| [ check.keyword_id, check.location ] }
          .transform_values { |checks| checks.max_by(&:checked_at) }

        tracked.map do |keyword_id, location|
          keyword = keywords[keyword_id]
          next if keyword.nil?

          check = latest[[ keyword_id, location ]]
          weight = weight_for(keyword_id)
          ctr = CtrCurve.at(check&.position)

          Row.new(keyword: keyword, query: keyword.query, location: location,
                  position: check&.position, ctr: ctr, weight: weight,
                  points: index_for(weight * ctr))
        end.select { |value| value }
      end
    end
  end
end
