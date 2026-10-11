module AhoyDashboard
  module Seo
    class ConversionPresenter < BasePresenter
      def tiles
        [
          Tile.new(label: "Search clicks", value: number(clicks), note: "Google's total for the range", tone: nil),
          Tile.new(label: "Search visits", value: number(result.visits), note: "counted on your site", tone: nil),
          Tile.new(label: "Converting visits", value: goals? ? number(result.converting_visits) : nil, note: "search visits that reached a goal", tone: nil),
          Tile.new(label: "Conversion rate", value: goals? ? percent(result.rate, places: 1) : nil, note: "of search visits", tone: nil),
          Tile.new(label: "Converting pages", value: goals? ? number(result.converting.size) : nil, note: nil, tone: nil),
          Tile.new(label: "Not converting", value: goals? ? number(result.leaking.size) : nil, note: "pages with traffic", tone: nil)
        ]
      end

      def rows
        result.rows
      end

      def clicks
        [ totals.clicks, result.clicks ].max
      end

      def unnamed_clicks
        clicks - result.clicks
      end

      def table_cols
        [ "minmax(0, 1.4fr)", "minmax(0, 1fr)", "68px", "68px", *([ "108px", "68px" ] if goals?) ].compact.join(" ")
      end

      def converting_label(row)
        number(row.converting)
      end

      def rate_note
        "Rate is the share of visits that converted at least once, so it cannot pass 100%. " \
          "A visit that completes two goals is one converting visit."
      end

      def named_note
        return nil unless unnamed_clicks.positive?

        "#{number(result.clicks)} of #{pluralize(number(clicks), "click")} landed on a page Google names. " \
          "The other #{number(unnamed_clicks)} are in the total and in no row."
      end

      def leaking
        result.leaking.first(15)
      end

      def goals?
        result.goals?
      end

      def goal_notice
        AhoyDashboard::SetupNotice.call(
          :goal, url: new_goal_path,
                 hint: "Clicks and visits still show below. Conversions show once a goal says which page visit or event counts."
        )
      end

      def conversions_label(row)
        goals? ? number(row.conversions) : DASH
      end

      def rate_label(row)
        goals? && row.landed? ? percent(row.conversion_rate, places: 1) : DASH
      end

      def csv_tables
        [
          CsvTable.new(key: "pages", label: "Pages, searches and conversions", headers: pages_headers) do
            rows.map do |row|
              values = [ row.path, row.query.presence, row.position, row.clicks, row.visits ]
              values += [ row.converting, (csv_percent(row.conversion_rate) if row.landed?) ] if goals?
              values
            end
          end,
          CsvTable.new(key: "leaking", label: "Search traffic with no conversions",
                       headers: [ "Page", "Top search", "Clicks", "Visits", "Position" ]) do
            leaking.map { |row| [ row.path, row.query.presence, row.clicks, row.visits, row.position ] }
          end
        ]
      end

      def mismatch_note
        "Google counts clicks on the results page. Your site counts visits in the browser. " \
          "The two never match exactly, so only a big gap means something."
      end

      private

      def pages_headers
        [ "Page", "Top search", "Position", "Clicks", "Visits", *([ "Converting visits", "Rate" ] if goals?) ]
      end
    end
  end
end
