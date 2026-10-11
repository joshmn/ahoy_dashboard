module AhoyDashboard
  module Seo
    class PositionChangesPresenter < BasePresenter
      Group = Data.define(:key, :title, :note, :rows, :tone)

      Move = Data.define(:key, :label, :count)

      def groups
        [
          Group.new(key: :lost, title: "Gone from the results", tone: :danger, rows: result.lost,
                    note: "Ranked at the start of the range, nowhere at the end."),
          Group.new(key: :declined, title: "Fell", tone: :warning, rows: result.declined,
                    note: "Still ranking, further down than it was."),
          Group.new(key: :gained, title: "Arrived", tone: :success, rows: result.gained,
                    note: "Nowhere at the start of the range, ranking at the end."),
          Group.new(key: :improved, title: "Climbed", tone: :success, rows: result.improved,
                    note: "Still ranking, further up than it was."),
          Group.new(key: :level, title: "Did not move", tone: :neutral, rows: holding,
                    note: "Same position at both ends. It may still have moved in between.")
        ].select { |group| group.rows.any? }
      end

      def moves
        [
          Move.new(key: :lost, label: "Gone", count: result.lost.size),
          Move.new(key: :declined, label: "Fell", count: result.declined.size),
          Move.new(key: :gained, label: "Arrived", count: result.gained.size),
          Move.new(key: :improved, label: "Climbed", count: result.improved.size),
          Move.new(key: :level, label: "Did not move", count: holding.size),
          Move.new(key: :unranked, label: "Not ranking", count: unranked.size)
        ]
      end

      def moves_label
        moves.map { |move| "#{move.label}: #{number(move.count)}" }.join(", ")
      end

      def anchor(key)
        "moves-#{key}"
      end

      def holding
        memo(:holding) { result.for(:level).select(&:ranked?) }
      end

      def unranked
        memo(:unranked) { result.for(:level).reject(&:ranked?) }
      end

      def crossings_note
        "#{number(result.onto_page_one.size)} crossed onto page one and " \
          "#{number(result.off_page_one.size)} fell off it."
      end

      def change_kind(row)
        case row.movement
        when :gained then :new
        when :lost then :gone
        when :level then row.ranked? ? :level : :none
        when :improved then :up
        else :down
        end
      end

      def places?
        memo(:places) { result.rows.map(&:location).uniq.many? }
      end

      def windows?
        memo(:windows) { result.rows.map { |row| window(row) }.uniq.many? }
      end

      def table_cols
        [ "minmax(0, 1.5fr)", ("96px" if places?), "72px", "72px", "112px", "minmax(0, 1fr)",
          ("132px" if windows?) ].compact.join(" ")
      end

      def window_note
        return nil if windows? || result.rows.empty?

        row = result.rows.first
        return "Every search here was read on #{on_label(row.first_at)}." if local_date(row.first_at) == local_date(row.last_at)

        "Every search here was first read #{on_label(row.first_at)} and last read #{on_label(row.last_at)}."
      end

      def position_label(value)
        value.nil? ? "Nowhere" : value.to_s
      end

      def window(row)
        return on_label(row.first_at) if local_date(row.first_at) == local_date(row.last_at)

        "#{on_label(row.first_at)} to #{on_label(row.last_at)}"
      end

      def comparable?
        result.comparable?
      end

      def csv_tables
        tables = groups.map do |group|
          CsvTable.new(key: group.key, label: group.title, headers: change_headers) do
            group.rows.map { |row| change_row(row) }
          end
        end

        tables << CsvTable.new(key: "unranked", label: "Not ranking", headers: unranked_headers) do
          unranked.map { |row| unranked_row(row) }
        end
      end

      private

      def change_headers
        [ "Search", ("Place" if places?), "Was", "Now", "Change", "URL", ("Between" if windows?) ].compact
      end

      def change_row(row)
        values = [ row.query ]
        values << row.place.label if places?
        values.push(row.from, row.to, csv_change(row), csv_url(row.url))
        values << window(row) if windows?
        values
      end

      def csv_change(row)
        case change_kind(row)
        when :new then "New"
        when :gone then "Gone"
        else row.change
        end
      end

      def csv_url(url)
        url.presence && path_of(url)
      end

      def unranked_headers
        [ "Search", ("Place" if places?) ].compact
      end

      def unranked_row(row)
        values = [ row.query ]
        values << row.place.label if places?
        values
      end
    end
  end
end
