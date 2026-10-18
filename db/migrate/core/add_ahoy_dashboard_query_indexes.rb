class AddAhoyDashboardQueryIndexes < ActiveRecord::Migration[6.0]
  disable_ddl_transaction!

  INDEXES = [
    {
      table: :ahoy_events, columns: %w[time visit_id],
      name: "index_ahoy_events_on_human_time_and_visit",
      where: "properties ->> 'crawler' IS NULL"
    },
    {
      table: :ahoy_dashboard_alert_events, columns: %w[check_id],
      name: "index_ahoy_dashboard_alert_events_on_check",
      where: "check_id IS NOT NULL"
    },
    {
      table: :ahoy_dashboard_alert_events, columns: %w[previous_check_id],
      name: "index_ahoy_dashboard_alert_events_on_previous_check",
      where: "previous_check_id IS NOT NULL"
    }
  ].freeze

  def up
    INDEXES.each do |definition|
      next unless table_exists?(definition[:table])

      existing = indexes(definition[:table])
      named = existing.find { |index| index.name == definition[:name] }
      check_definition!(named, definition) if named

      if named && !valid_index?(named)
        remove_index definition[:table], name: named.name, algorithm: :concurrently
      end
      next if existing.any? { |index| valid_index?(index) && equivalent?(index, definition) }

      add_index definition[:table], definition[:columns], name: definition[:name],
                where: definition[:where], algorithm: :concurrently
    end
  end

  def down
    INDEXES.reverse_each do |definition|
      next unless table_exists?(definition[:table])

      named = indexes(definition[:table]).find { |index| index.name == definition[:name] }
      next unless named

      check_definition!(named, definition)
      remove_index definition[:table], name: named.name, algorithm: :concurrently
    end
  end

  private

  def check_definition!(index, definition)
    return if equivalent?(index, definition)

    raise ActiveRecord::MigrationError,
          "Index #{definition[:name]} already exists with a different definition; leaving it unchanged"
  end

  def equivalent?(index, definition)
    !index.unique && index.using.to_s == "btree" && index.columns == definition[:columns] &&
      index.orders.empty? && index.opclasses.empty? && no_included_columns?(index) &&
      predicate(index.where) == predicate(definition[:where])
  end

  def valid_index?(index)
    return index.valid? if index.respond_to?(:valid?)

    select_value("SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE i.indrelid = #{quote(index.table)}::regclass AND c.relname = #{quote(index.name)}")
  end

  def no_included_columns?(index)
    return Array(index.include).empty? if index.respond_to?(:include)

    select_value("SELECT i.indnkeyatts = i.indnatts FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE i.indrelid = #{quote(index.table)}::regclass AND c.relname = #{quote(index.name)}")
  end

  def predicate(value)
    value.to_s.split(/('(?:[^']|'')*'|"(?:[^"]|"")*")/).map do |token|
      if token.start_with?("'")
        token
      elsif token.start_with?('"')
        identifier = token[1...-1]
        identifier.match?(/\A[a-z_][a-z0-9_]*\z/) ? identifier : token
      else
        token.downcase.gsub(/::\s*text\b/, "").gsub(/[\s()]/, "")
      end
    end.join
  end
end
