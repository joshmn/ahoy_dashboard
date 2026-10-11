class AddAhoyDashboardAlertCheckForeignKeys < ActiveRecord::Migration[6.0]
  EVENTS = :ahoy_dashboard_alert_events
  CHECKS = :ahoy_dashboard_serp_checks
  COLUMNS = %i[check_id previous_check_id].freeze

  def up
    return unless table_exists?(EVENTS)

    COLUMNS.each do |column|
      next if foreign_key_exists?(EVENTS, CHECKS, column: column)

      execute <<~SQL.squish
        update #{EVENTS} set #{column} = null
        where #{column} is not null
          and not exists (select 1 from #{CHECKS} where #{CHECKS}.id = #{EVENTS}.#{column})
      SQL
      add_foreign_key EVENTS, CHECKS, column: column, on_delete: :nullify
    end
  end

  def down
    return unless table_exists?(EVENTS)

    COLUMNS.each do |column|
      remove_foreign_key EVENTS, CHECKS, column: column if foreign_key_exists?(EVENTS, CHECKS, column: column)
    end
  end
end
