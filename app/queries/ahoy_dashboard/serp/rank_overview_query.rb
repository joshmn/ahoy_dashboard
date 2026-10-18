module AhoyDashboard
  module Serp
    class RankOverviewQuery
      Row = Data.define(:keyword, :location, :current, :previous, :best, :worst, :count) do
        include Placed

        def position
          current&.position
        end

        def ranked?
          position.present?
        end

        def url
          current&.url
        end

        def change
          return nil if position.nil? || previous&.position.nil?

          previous.position - position
        end

        def arrived?
          ranked? && previous.present? && previous.position.nil?
        end

        def lost?
          !ranked? && previous&.position.present?
        end

        def overview?
          current&.ai_overview_present.present?
        end

        def cited?
          current&.ai_overview_cited.present?
        end
      end

      Result = Data.define(:site, :range, :rows, :tracked, :ranked, :top_three, :top_ten,
                           :median, :overviews, :cited) do
        def any?
          rows.any?
        end

        def share(count)
          tracked.zero? ? 0.0 : count.to_f / tracked
        end
      end

      def self.call(**options)
        new(**options).call
      end

      def initialize(site:, range:, tag: nil)
        @site = site
        @range = range
        @tag = tag
      end

      def call
        rows = build_rows
        AhoyDashboard::PreloadAssociationsService.call(
          records: rows.reject(&:ranked?).map(&:current), associations: :run
        )

        Result.new(
          site: site, range: range, rows: rows, tracked: rows.size,
          ranked: rows.count(&:ranked?),
          top_three: rows.count { |row| row.ranked? && row.position <= 3 },
          top_ten: rows.count { |row| row.ranked? && row.position <= 10 },
          median: Median.of(rows.map(&:position)), overviews: rows.count(&:overview?), cited: rows.count(&:cited?)
        )
      end

      private

      attr_reader :site, :range, :tag

      def build_rows
        grouped.map { |(_keyword_id, location), checks| row_for(location, checks) }
          .sort_by { |row| [ row.ranked? ? 0 : 1, row.position || 0, row.keyword.query, row.location ] }
      end

      def grouped
        return {} if site.nil?

        history = SerpCheck.success.where(site_id: site.id)
          .in_range(range)
          .for_tag(tag)
          .at_current_places
          .select(
            "ahoy_dashboard_serp_checks.*",
            "row_number() over (partition by keyword_id, location order by checked_at desc, id desc) as history_recency",
            "min(position) over (partition by keyword_id, location) as history_best",
            "max(position) over (partition by keyword_id, location) as history_worst",
            "count(*) over (partition by keyword_id, location) as history_count",
            "min(checked_at) over (partition by keyword_id, location) as history_started_at",
            "last_value(id) over (partition by keyword_id, location order by checked_at desc, id desc " \
              "rows between unbounded preceding and unbounded following) as history_first_id"
          )

        SerpCheck.from(history, :ahoy_dashboard_serp_checks)
          .where("history_recency <= 2")
          .includes(:keyword)
          .order(Arel.sql("history_started_at, history_first_id, checked_at, id"))
          .group_by { |check| [ check.keyword_id, check.location ] }
      end

      def row_for(location, checks)
        current = checks.last

        Row.new(
          keyword: current.keyword, location: location, current: current,
          previous: checks[-2], best: current[:history_best], worst: current[:history_worst],
          count: current[:history_count]
        )
      end
    end
  end
end
