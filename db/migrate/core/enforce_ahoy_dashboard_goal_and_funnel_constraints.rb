# frozen_string_literal: true

class EnforceAhoyDashboardGoalAndFunnelConstraints < ActiveRecord::Migration[6.0]
  DEFINITION_INDEX = "index_ahoy_dashboard_goals_on_null_safe_definition".freeze
  NAME_INDEX = "index_ahoy_dashboard_goals_on_effective_name".freeze
  SLOT_INDEX = "ahoy_dashboard_funnel_steps_on_slot".freeze
  NAME_EXPRESSION = <<~SQL.squish.freeze
    (COALESCE(CASE WHEN display_name ~ '[^[:space:]]' THEN display_name ELSE NULL END,
      CASE WHEN kind = 1 THEN COALESCE(path_pattern, '')
        WHEN property_key ~ '[^[:space:]]' THEN
          COALESCE(event_name, '') || ' (' || property_key || ': ' || COALESCE(property_value, '') || ')'
        ELSE COALESCE(event_name, '') END))
  SQL

  def up
    definition = ["kind", *%w[event_name path_pattern property_key property_value].flat_map do |column|
      ["(#{column} IS NULL)", "COALESCE(#{column}, '')"]
    end].join(", ")
    ensure_unique!(definition, "definitions")
    ensure_unique!(NAME_EXPRESSION, "effective names")
    ensure_index(:ahoy_dashboard_goals, definition, DEFINITION_INDEX)
    ensure_index(:ahoy_dashboard_goals, NAME_EXPRESSION, NAME_INDEX)
    legacy = indexes(:ahoy_dashboard_goals).find { |index| index.name == "index_ahoy_dashboard_goals_on_definition" }
    if legacy && legacy.unique && legacy.columns == %w[kind event_name path_pattern property_key property_value]
      remove_index(:ahoy_dashboard_goals, name: legacy.name)
    end
    replace_deferred_slot_constraint
  end

  def down
  end

  private

  def ensure_unique!(expression, label)
    duplicates = select_values("SELECT array_agg(id ORDER BY id)::text FROM ahoy_dashboard_goals GROUP BY #{expression} HAVING count(*) > 1 LIMIT 10")
    return if duplicates.empty?

    raise ActiveRecord::MigrationError, "Goals have duplicate #{label}; resolve these IDs before retrying: #{duplicates.join(', ')}"
  end

  def ensure_index(table, columns, name)
    existing = indexes(table).find { |index| index.name == name }
    if existing
      valid = select_value("SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE i.indrelid = #{quote(table)}::regclass AND c.relname = #{quote(name)}")
      return if valid && existing.unique && existing.where.nil? && normalize(existing.columns) == normalize(columns)

      raise ActiveRecord::MigrationError, "Index #{name} has another definition; leaving it unchanged"
    end
    add_index(table, columns, unique: true, name: name)
  end

  def normalize(expression)
    Array(expression).join(",").split(/('(?:[^']|'')*')/).map do |token|
      token.start_with?("'") ? token : token.downcase.gsub(/::(?:character varying|text)|[\s()]/, "")
    end.join
  end

  def replace_deferred_slot_constraint
    constraint = select_one(<<~SQL)
      SELECT conkey = ARRAY[
        (SELECT attnum FROM pg_attribute WHERE attrelid = c.conrelid AND attname = 'funnel_id'),
        (SELECT attnum FROM pg_attribute WHERE attrelid = c.conrelid AND attname = 'position')
      ] AS matching_columns
      FROM pg_constraint c
      WHERE conrelid = 'ahoy_dashboard_funnel_steps'::regclass
        AND conname = #{quote(SLOT_INDEX)} AND contype = 'u'
    SQL
    if constraint
      unless constraint.fetch("matching_columns")
        raise ActiveRecord::MigrationError, "Constraint #{SLOT_INDEX} has another definition; leaving it unchanged"
      end
      execute("ALTER TABLE ahoy_dashboard_funnel_steps DROP CONSTRAINT #{quote_column_name(SLOT_INDEX)}")
    end
    ensure_index(:ahoy_dashboard_funnel_steps, [:funnel_id, :position], SLOT_INDEX)
  end
end
