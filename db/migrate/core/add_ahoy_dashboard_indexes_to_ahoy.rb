# frozen_string_literal: true

class AddAhoyDashboardIndexesToAhoy < ActiveRecord::Migration[6.0]
  disable_ddl_transaction!

  INDEXES = { ahoy_visits: :started_at, ahoy_events: :time }.freeze

  def up
    INDEXES.each do |table, column|
      name = "index_#{table}_on_dashboard_#{column}"
      existing = indexes(table)
      named = existing.find { |index| index.name == name }
      if named && !equivalent?(named, column)
        raise ActiveRecord::MigrationError, "Index #{name} has another definition; leaving it unchanged"
      end
      remove_index(table, name: name, algorithm: :concurrently) if named && !valid?(named)
      next if existing.any? { |index| equivalent?(index, column) && valid?(index) }

      add_index(table, column, name: name, algorithm: :concurrently)
    end
  end

  def down
  end

  private

  def equivalent?(index, column)
    !index.unique && index.columns == [column.to_s] && index.using.to_s == "btree" && index.where.nil?
  end

  def valid?(index)
    return index.valid? if index.respond_to?(:valid?)

    select_value("SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE i.indrelid = #{quote(index.table)}::regclass AND c.relname = #{quote(index.name)}")
  end
end
