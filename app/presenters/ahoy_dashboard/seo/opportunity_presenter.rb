module AhoyDashboard
  module Seo
    class OpportunityPresenter < BasePresenter
      LISTED = 30

      delegate :rows, to: :result

      def tracking_phrases
        (listed + striking + under_performing).map(&:query)
      end

      def tiles
        [
          Tile.new(label: "Clicks on these searches", value: number(result.clicks), note: listed_note, tone: nil),
          Tile.new(label: "Impressions", value: number(result.impressions), note: "on these searches", tone: nil),
          Tile.new(label: "Upside", value: number(result.upside), note: "clicks at position three", tone: nil),
          Tile.new(label: "Striking distance", value: number(result.striking_count), note: "eleven to twenty", tone: nil),
          Tile.new(label: "Below expected", value: number(result.under_performing_count), note: "fewer clicks than the position gets", tone: nil)
        ]
      end

      def listed
        rows.first(LISTED)
      end

      def listed_note
        return "over the range" unless totals.any?

        "of #{number([ totals.clicks, result.clicks ].max)} in total"
      end

      def striking
        result.striking(limit: 20)
      end

      def under_performing
        result.under_performing(limit: 15)
      end

      def band_tone(row)
        case row.band
        when "Holding" then :success
        when "Page one" then :success
        when "Striking distance" then :warning
        else :neutral
        end
      end

      def target
        CtrCurve::REALISTIC_TARGET
      end

      def upside_note
        "Upside is the extra clicks a move to #{ActiveSupport::Inflector.ordinalize(target)} place would bring, " \
          "based on typical click rates by position. Use it to sort the list, not as a forecast."
      end

      def impressions_note
        "Position and impressions come straight from Google. Upside is an estimate from typical click rates."
      end

      def under_note
        "Fewer clicks than the position usually returns. Look at the title and the snippet."
      end

      def csv_tables
        [
          CsvTable.new(key: "worth_most", label: "Worth the most",
                       headers: [ "Search", "Clicks", "Impressions", "Position", "CTR", "Upside", "Band",
                                  "Landing page" ]) do
            listed.map do |row|
              [ row.query, row.clicks, row.impressions, row.position, csv_percent(row.ctr), row.upside, row.band,
                Formatting.url_path(row.page) ]
            end
          end,
          CsvTable.new(key: "striking", label: "Striking distance",
                       headers: [ "Search", "Position", "Impressions", "Upside" ]) do
            striking.map { |row| [ row.query, row.position, row.impressions, row.upside ] }
          end,
          CsvTable.new(key: "under_performing", label: "Below expected clicks",
                       headers: [ "Search", "Position", "Clicks", "Expected" ]) do
            under_performing.map { |row| [ row.query, row.position, row.clicks, row.expected ] }
          end
        ]
      end
    end
  end
end
