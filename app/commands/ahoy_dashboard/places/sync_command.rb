module AhoyDashboard
  module Places
    class SyncCommand < AhoyDashboard::Command
      BATCH = 2_000

      FLOOR = 1_000
      KEEP_SHARE = 0.9

      COLUMNS = %i[parent_code name label country_code kind depth synced_at].freeze

      Outcome = Data.define(:written, :removed, :month, :total)

      def initialize(on: nil, source: nil)
        @source = source || Source.new(on: on)
      end

      def call
        return broadcast(:off) unless Places.enabled?

        started = Time.current
        written = write(started)

        return broadcast(:empty, source.month) if written.zero?

        removed = prune(started, written)
        count_children

        broadcast(:ok, Outcome.new(written: written, removed: removed, month: source.month, total: Place.count))
      rescue Error => e
        broadcast(:failed, e)
      end

      private

      attr_reader :source

      def write(started)
        written = 0

        source.each_slice(BATCH) do |rows|
          Place.upsert_all(rows.map { |row| row.to_h.merge(synced_at: started) },
                           unique_by: :code, update_only: COLUMNS, record_timestamps: true)
          written += rows.size
        end

        written
      end

      def prune(started, written)
        return 0 if written < FLOOR
        return 0 if written < Place.count * KEEP_SHARE

        Place.where(Place.arel_table[:synced_at].lt(started)).delete_all
      end

      def count_children
        table = Place.quoted_table_name

        Place.connection.execute(<<~SQL.squish)
          update #{table} as p
          set children_count = coalesce(c.total, 0)
          from (
            select parent_code, count(*) as total
            from #{table}
            where parent_code is not null
            group by parent_code
          ) as c
          where p.code = c.parent_code and p.children_count is distinct from c.total
        SQL

        Place.connection.execute(<<~SQL.squish)
          update #{table}
          set children_count = 0
          where children_count <> 0
            and code not in (select parent_code from #{table} where parent_code is not null)
        SQL
      end
    end
  end
end
