module AhoyDashboard
  module Seo
    class CannibalizationPresenter < BasePresenter
      delegate :rows, to: :result

      def tracking_phrases
        rows.map(&:query)
      end

      def tiles
        [
          Tile.new(label: "Contested", value: number(result.rows.size), note: "searches with more than one page", tone: nil),
          Tile.new(label: "Serious", value: number(result.high.size), note: "clicks split, positions swapping", tone: nil),
          Tile.new(label: "Worth watching", value: number(result.of(:medium).size), note: "one of the two", tone: nil),
          Tile.new(label: "Harmless", value: number(result.of(:low).size), note: "one page clearly wins", tone: nil),
          Tile.new(label: "Clicks on other pages", value: number(result.clicks_at_risk), note: "not the top page", tone: nil)
        ]
      end

      def severity_tone(severity)
        AhoyDashboard::SeverityBadge.tone(severity)
      end

      def severity_label(severity)
        case severity
        when :high then "Split and swapping"
        when :medium then "Worth a look"
        else "One page wins"
        end
      end

      def standing_label(row, page)
        return "Top page" if page == row.winner
        return "Second" if page == row.runner_up

        "Also shown"
      end

      def standing_tone(row, page)
        case standing_label(row, page)
        when "Top page" then :success
        when "Second" then :warning
        else :neutral
        end
      end

      def csv_tables
        [
          CsvTable.new(key: "pages", label: "Pages ranking for these searches",
                       headers: [ "Search", "Severity", "Page", "Clicks", "Impressions", "Position", "Days",
                                  "Standing" ]) do
            rows.flat_map do |row|
              row.pages.map do |page|
                [ row.query, severity_label(row.severity), page.path, page.clicks, page.impressions, page.position,
                  page.days, standing_label(row, page) ]
              end
            end
          end
        ]
      end

      def diagnosis(row)
        parts = []
        parts << "#{percent(row.split)} of the clicks are going to the second page" if row.split?
        parts << swapping_phrase(row) if row.swapping?

        (parts.any? ? parts.join(", and ") : "the top page is taking almost all of the clicks").upcase_first
      end

      def swapping_phrase(row)
        gap = (row.winner.position - row.runner_up.position).abs.round(1)

        return "the top two pages share the same average position" if gap.zero?

        "positions are #{gap} places apart"
      end

      def withholding_note
        "No search has more than one of your pages showing with enough impressions to judge. " \
          "Google leaves out low-volume searches here, so small overlaps may not show."
      end
    end
  end
end
