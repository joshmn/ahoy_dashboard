module AhoyDashboard
  module Seo
    class KeywordGapPresenter < BasePresenter
      delegate :rivals, :presence, to: :result

      def tiles
        [
          Tile.new(label: "Searches", value: number(result.rows.size), note: "compared"),
          Tile.new(label: "Missing", value: number(result.count_of(:missing)), note: "they rank, we do not", url: jump(:missing)),
          Tile.new(label: "Behind", value: number(result.count_of(:weak)), note: "we rank, worse", url: jump(:weak)),
          Tile.new(label: "Ahead", value: number(result.count_of(:strong)), note: "better than all of them", url: jump(:strong)),
          Tile.new(label: "Uncontested", value: number(result.count_of(:alone)), note: "only we turn up", url: jump(:alone)),
          Tile.new(label: "Rivals", value: number(result.attached.size), note: "attached to these searches")
        ]
      end

      def jump(key)
        result.count_of(key).positive? ? "#gap-#{key}" : nil
      end

      def no_rivals?
        rivals.empty?
      end

      def competitor_notice
        AhoyDashboard::SetupNotice.call(:competitor, url: new_site_path)
      end

      def groups
        [
          Group.new(key: :missing, title: "Missing", tone: :danger, rows: result.missing,
                    note: "They are on the page and we are not."),
          Group.new(key: :weak, title: "Behind", tone: :warning, rows: result.weak,
                    note: "We rank, they rank better. Sorted by how far behind."),
          Group.new(key: :strong, title: "Ahead", tone: :success, rows: result.strong,
                    note: "Ahead of every rival on the page."),
          Group.new(key: :alone, title: "Uncontested", tone: :success, rows: result.alone,
                    note: "We turn up and none of them do."),
          Group.new(key: :nobody, title: "Nobody ranks", tone: :neutral, rows: result.nobody,
                    note: "Neither we nor any competitor turned up.")
        ].select { |group| group.rows.any? }
      end

      def position_label(standing)
        standing_position(standing).to_s
      end

      def gap_kind(row)
        movement(row.gap)
      end

      def gap_text(row)
        return nil if row.gap.nil? || row.gap.zero?

        "#{row.gap.positive? ? "Ahead by" : "Behind by"} #{row.gap.abs}"
      end

      def places?
        memo(:places) { result.rows.map(&:location).uniq.many? }
      end

      def table_cols
        [ "minmax(0, 1.4fr)", ("112px" if places?), "72px", *rivals.map { "104px" }, "120px" ].compact.join(" ")
      end

      def csv_tables
        tables = [
          CsvTable.new(key: "competitors", label: "How often each competitor shows up",
                       headers: [ "Competitor", "Domain", "Share of searches", "Searches" ]) do
            presence.map { |rival, appearances, share| [ rival.name, rival.domain, csv_percent(share), appearances ] }
          end
        ]

        groups.each do |group|
          tables << CsvTable.new(key: group.key, label: group.title, headers: gap_headers) do
            group.rows.map { |row| gap_row(row) }
          end
        end

        tables
      end

      private

      def gap_headers
        [ "Search", ("Place" if places?), "You", *rivals.map(&:name), "Gap" ].compact
      end

      def gap_row(row)
        values = [ row.query ]
        values << row.place.label if places?
        values << standing_position(row.ours)
        row.rivals.each { |standing| values << standing_position(standing) }
        values << row.gap
      end

      def standing_position(standing)
        return "Not tracked" if standing.nil? || !standing.tracked?
        return "Nowhere" unless standing.ranked?

        standing.position
      end
    end
  end
end
