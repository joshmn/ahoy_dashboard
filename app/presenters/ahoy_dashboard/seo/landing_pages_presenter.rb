module AhoyDashboard
  module Seo
    class LandingPagesPresenter < BasePresenter
      delegate :pages, :lost, to: :result

      def tiles
        [
          Tile.new(label: "Pages ranking", value: number(result.pages.size), note: "on the latest reading"),
          Tile.new(label: "Searches held", value: number(result.held), note: "of #{number(result.tracked)} tracked"),
          Tile.new(label: "Top page", value: top_share, note: top_note),
          Tile.new(label: "Lost every search", value: number(result.lost.size),
                   note: "pages that held one earlier", tone: (:bad if result.lost.any?))
        ]
      end

      def places?
        memo(:places) { (pages.flat_map(&:held) + lost.flat_map(&:gone)).map(&:location).uniq.many? }
      end

      def table_cols
        "minmax(0, 1.8fr) 88px 72px 80px 132px"
      end

      def lost_cols
        [ "minmax(0, 1.4fr)", ("112px" if places?), "72px", "minmax(0, 1.2fr)" ].compact.join(" ")
      end

      def searches_label(page)
        pluralize(page.searches, "search")
      end

      def share_label(page)
        percent(page.share, places: 1)
      end

      def gone_now(row)
        return "Not in the results" unless row.ranked_elsewhere?

        "#{row.now_position} on #{path_of(row.now_url)}"
      end

      def points_note
        return "None of these searches rank high enough to earn clicks, so every share reads 0%." if result.points.zero?

        "Share of visibility is each page's click-rate points as a share of what all your tracked searches earn."
      end

      def unheld_note
        return nil if result.unheld.zero?

        "#{pluralize(result.unheld, 'tracked search')} did not rank on the latest reading, so no page holds them."
      end

      def csv_tables
        [
          CsvTable.new(key: "pages", label: "Pages carrying your rankings",
                       headers: [ "URL", "Searches", "Best", "Median", "Share of visibility" ]) do
            pages.map { |page| [ path_of(page.url), page.searches, page.best, page.median, csv_percent(page.share) ] }
          end,
          CsvTable.new(key: "held", label: "Searches held", headers: held_headers) do
            pages.flat_map { |page| page.held.map { |row| held_row(page, row) } }
          end,
          CsvTable.new(key: "lost", label: "Lost every search", headers: lost_headers) do
            lost.flat_map { |page| page.gone.map { |row| lost_row(page, row) } }
          end
        ]
      end

      private

      def held_headers
        [ "URL", "Search", ("Place" if places?), "Position" ].compact
      end

      def held_row(page, row)
        values = [ path_of(page.url), row.query ]
        values << row.place.label if places?
        values << row.position
      end

      def lost_headers
        [ "URL", "Search", ("Place" if places?), "Was", "Now", "Now URL" ].compact
      end

      def lost_row(page, row)
        values = [ path_of(page.url), row.query ]
        values << row.place.label if places?
        values.push(row.was, row.now_position, Formatting.url_path(row.now_url))
      end

      def top_share
        result.top ? share_label(result.top) : DASH
      end

      def top_note
        result.top ? truncate(path_of(result.top.url), length: 32) : "no page ranks"
      end
    end
  end
end
