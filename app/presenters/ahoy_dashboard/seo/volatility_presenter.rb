module AhoyDashboard
  module Seo
    class VolatilityPresenter < BasePresenter
      def tiles
        [
          Tile.new(label: "Volatility", value: result.score.to_s, note: result.level, tone: nil),
          Tile.new(label: current_title, value: current_label, note: on_label(result.current&.on), tone: nil),
          Tile.new(label: "Peak", value: peak_label, note: on_label(result.peak&.on), tone: nil),
          Tile.new(label: "Comparisons", value: number(result.readings), note: "consecutive readings", tone: nil),
          Tile.new(label: "Depth", value: "Top #{result.depth}", note: "of every reading", tone: nil),
          Tile.new(label: "Days", value: number(result.points.size), note: "with something to compare", tone: nil)
        ]
      end

      def current_label
        result.current.nil? ? DASH : result.current.score.to_s
      end

      def current_title
        result.current&.on == AhoyDashboard.time_zone.today ? "Today" : "Latest day"
      end

      def peak_label
        result.peak.nil? ? DASH : result.peak.score.to_s
      end

      def points
        result.points.map { |point| [ on_label(point.on), point.score ] }
      end

      BUSIEST_SHOWN = 8

      def busiest
        memo(:busiest) { result.busiest.first(40) }
      end

      def busiest_head
        busiest.first(BUSIEST_SHOWN)
      end

      def busiest_rest
        busiest.drop(BUSIEST_SHOWN)
      end

      def arrived(busy)
        busy.arrived.map { |link| AhoyDashboard::Serp::Domain.host(link) }.select { |value| value }.uniq.first(3)
      end

      def level_scale
        VolatilityQuery::LEVELS
      end

      def csv_tables
        [
          CsvTable.new(key: "searches", label: "Most changed searches",
                       headers: [ "Search", "Day", "Score", "Turnover", "Shuffle", "New on the page" ]) do
            busiest.map do |busy|
              [ busy.query, csv_date(busy.on), busy.score.round(1), csv_percent(busy.turnover),
                csv_percent(busy.shuffle), arrived(busy).join(", ").presence ]
            end
          end
        ]
      end
    end
  end
end
