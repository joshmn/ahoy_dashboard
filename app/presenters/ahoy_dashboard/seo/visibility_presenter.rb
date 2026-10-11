module AhoyDashboard
  module Seo
    class VisibilityPresenter < BasePresenter
      def tiles
        [
          Tile.new(label: "Visibility", value: index_label, note: change_label, tone: tone_for(result.change)),
          Tile.new(label: "Ranking", value: number(result.ranked), note: "of #{number(result.tracked)} tracked", tone: nil),
          Tile.new(label: "Best day", value: point_label(result.best), note: on_label(result.best&.on), tone: nil),
          Tile.new(label: "Worst day", value: point_label(result.worst), note: on_label(result.worst&.on), tone: nil),
          Tile.new(label: "Weighting", value: weighting_label, note: weighting_note, tone: nil),
          Tile.new(label: "Readings", value: number(result.points.size), note: "days with a check", tone: nil)
        ]
      end

      def index_label
        result.index.nil? ? DASH : "#{result.index.round(1)}"
      end

      def point_label(point)
        point.nil? ? DASH : point.index.round(1).to_s
      end

      def change_label
        return "no earlier reading" if result.change.nil?

        "#{signed(result.change, places: 1)} over the range"
      end

      def weighting_label
        result.weighted? ? "Impressions" : "Even"
      end

      def weighting_note
        return "asked for impressions, found none" if result.fell_back?
        return "each search by its own demand" if result.weighted?

        "every search counts the same"
      end

      def points
        result.points.map { |point| [ on_label(point.on), point.index ] }
      end

      def contributors
        result.contributors
      end

      def dead
        result.dead
      end

      def places?
        memo(:places) { (result.contributors + result.dead).map(&:location).uniq.many? }
      end

      def table_cols
        [ "minmax(0, 1.6fr)", ("130px" if places?), "76px", "90px", "72px", "132px" ].compact.join(" ")
      end

      def weightable?
        AhoyDashboard::SearchConsole.installed?
      end

      def weighting_reason
        AhoyDashboard::SeoHelper.not_installed_reason(:search_console)
      end

      def weighting_options
        %i[even impressions].map do |mode|
          {
            key: mode,
            label: mode == :even ? "Even" : "By impressions",
            url: surface.path(query.to_query.merge(link_param).merge(weighting: mode)),
            active: result.weighting == mode
          }
        end
      end

      def contribution(row)
        earned.zero? ? 0.0 : row.points / earned
      end

      def earned
        memo(:earned) { result.contributors.sum(&:points).to_f }
      end

      def ceiling_note
        "A hundred is every tracked search finishing first. A genuine top three " \
          "across a whole set lands somewhere in the twenties."
      end

      def csv_tables
        [
          CsvTable.new(key: "contributors", label: "Top contributors", headers: contributor_headers) do
            contributors.map { |row| contributor_row(row) }
          end,
          CsvTable.new(key: "not_ranking", label: "Not ranking", headers: dead_headers) do
            dead.map { |row| dead_row(row) }
          end
        ]
      end

      private

      def place_label(row)
        Serp::Location.parse(row.location).label
      end

      def contributor_headers
        [ "Search", ("Place" if places?), "Position", "Click rate", "Points", "Share" ].compact
      end

      def contributor_row(row)
        values = [ row.query ]
        values << place_label(row) if places?
        values.push(row.position, csv_percent(row.ctr), row.points.round(2), csv_percent(contribution(row)))
      end

      def dead_headers
        [ "Search", ("Place" if places?) ].compact
      end

      def dead_row(row)
        values = [ row.query ]
        values << place_label(row) if places?
        values
      end
    end
  end
end
