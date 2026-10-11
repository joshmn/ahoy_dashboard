# frozen_string_literal: true

module AhoyDashboard

  class EventStatistics
    class DefinitionConflict < StandardError; end

    TABLE = "ahoy_events".freeze
    ALL = {
      "ahoy_dashboard_events_crawler" => "(properties ->> 'crawler')",
      "ahoy_dashboard_events_path" => "(properties ->> 'path')",
      "ahoy_dashboard_events_format" => "(properties ->> 'format')",
      "ahoy_dashboard_events_controller" => "(properties ->> 'controller')",
      "ahoy_dashboard_events_name_path" => "name, (properties ->> 'path')"
    }.freeze
    FORMER = %w[events_path events_name_path dash_events_crawler dash_events_format dash_events_controller
                telemetry_events_crawler telemetry_events_path telemetry_events_format
                telemetry_events_controller telemetry_events_name_path].freeze

    class << self
      def apply!(analyze: true)
        changed = false
        ALL.each do |name, expression|
          existing = catalog.find { |row| row["stxname"] == name }
          if existing
            raise DefinitionConflict, "Statistics #{name} already exists with another definition" unless matching?(existing, expression)
            next
          end
          connection.execute("CREATE STATISTICS #{qualified(name)} ON #{expression} FROM #{qualified(TABLE)}")
          changed = true
        end
        connection.execute("ANALYZE #{qualified(TABLE)}") if analyze && changed
        ALL.keys
      end

      def remove!
        catalog.each do |row|
          expression = ALL[row["stxname"]]
          next unless expression && matching?(row, expression)

          connection.execute("DROP STATISTICS #{qualified(row['stxname'])}")
        end
      end

      def present
        catalog.select { |row| ALL[row["stxname"]] && matching?(row, ALL[row["stxname"]]) }.map { |row| row["stxname"] }
      end

      def former
        catalog.select { |row| FORMER.include?(row["stxname"]) && row["table_oid"].to_i == table.fetch("oid").to_i }
          .map { |row| row["stxname"] }
      end

      def missing
        ALL.keys - present
      end

      private

      def connection
        ActiveRecord::Base.connection
      end

      def table
        connection.select_one("SELECT c.oid, n.nspname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.oid = #{connection.quote(TABLE)}::regclass")
      end

      def qualified(name)
        "#{connection.quote_column_name(table.fetch('nspname'))}.#{connection.quote_column_name(name)}"
      end

      def catalog
        connection.select_all(<<~SQL).to_a
          SELECT stxname, stxrelid AS table_oid, pg_get_statisticsobjdef(s.oid) AS definition
          FROM pg_statistic_ext s JOIN pg_namespace n ON n.oid = s.stxnamespace
          WHERE n.nspname = #{connection.quote(table.fetch("nspname"))}
        SQL
      end

      def matching?(row, expression)
        actual = row.fetch("definition").split(" ON ", 2).last.split(" FROM ", 2).first
        row.fetch("table_oid").to_i == table.fetch("oid").to_i && normalize(actual) == normalize(expression)
      end

      def normalize(expression)
        expression.split(/('(?:[^']|'')*')/).map do |token|
          token.start_with?("'") ? token : token.gsub(/::text|[\s()]/, "")
        end.join
      end
    end
  end
end
