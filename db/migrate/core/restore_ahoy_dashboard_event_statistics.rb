# frozen_string_literal: true

class RestoreAhoyDashboardEventStatistics < ActiveRecord::Migration[6.0]
  STATISTICS = {
    "ahoy_dashboard_events_crawler" => "(properties ->> 'crawler')",
    "ahoy_dashboard_events_path" => "(properties ->> 'path')",
    "ahoy_dashboard_events_format" => "(properties ->> 'format')",
    "ahoy_dashboard_events_controller" => "(properties ->> 'controller')",
    "ahoy_dashboard_events_name_path" => "name, (properties ->> 'path')"
  }.freeze

  def up
    schema = select_value("SELECT n.nspname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.oid = 'ahoy_events'::regclass")
    STATISTICS.each do |name, expression|
      existing = select_one("SELECT stxrelid = 'ahoy_events'::regclass AS matching_table, pg_get_statisticsobjdef(oid) AS definition FROM pg_statistic_ext WHERE stxname = #{quote(name)} AND stxnamespace = #{quote(schema)}::regnamespace")
      if existing
        actual = existing.fetch("definition").split(" ON ", 2).last.split(" FROM ", 2).first
        unless existing.fetch("matching_table") && normalize(actual) == normalize(expression)
          raise ActiveRecord::MigrationError, "Statistics #{name} has another definition; leaving it unchanged"
        end
        next
      end
      execute("CREATE STATISTICS #{quote_column_name(schema)}.#{quote_column_name(name)} ON #{expression} FROM #{quote_column_name(schema)}.ahoy_events")
    end
    execute("ANALYZE ahoy_events")
  end

  def down
  end

  private

  def normalize(expression)
    expression.split(/('(?:[^']|'')*')/).map do |token|
      token.start_with?("'") ? token : token.gsub(/::text|[\s()]/, "")
    end.join
  end
end
