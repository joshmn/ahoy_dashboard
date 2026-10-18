class CreateAhoyDashboardAlertTables < ActiveRecord::Migration[6.0]
  CHECKS = :ahoy_dashboard_serp_checks

  def up
    create_table :ahoy_dashboard_alert_rules do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.boolean :enabled, null: false, default: false
      t.integer :threshold
      t.integer :floor
      t.integer :severity, null: false, default: 1
      t.datetime :last_fired_at
      t.datetime :last_checked_at
      t.integer :fired_count, null: false, default: 0
      t.timestamps
    end

    add_index :ahoy_dashboard_alert_rules, :key, unique: true

    create_table :ahoy_dashboard_alert_events do |t|
      t.references :rule, null: false,
                   foreign_key: { to_table: :ahoy_dashboard_alert_rules, on_delete: :cascade },
                   index: { name: "index_ahoy_dashboard_alert_events_on_rule" }
      t.bigint :check_id
      t.bigint :previous_check_id
      t.datetime :fired_at, null: false
      t.integer :severity, null: false, default: 1
      t.string :headline, null: false
      t.string :detail
      t.string :subject, null: false
      t.string :reading
      t.boolean :sample_data, null: false, default: false
      t.datetime :cleared_at
      t.datetime :delivered_at
      t.string :delivery_error
      t.timestamps
    end

    add_index :ahoy_dashboard_alert_events, [ :rule_id, :check_id ], unique: true,
              name: "index_ahoy_dashboard_alert_events_on_saying"
    add_index :ahoy_dashboard_alert_events, [ :rule_id, :subject, :reading ], unique: true,
              where: "reading is not null", name: "index_ahoy_dashboard_alert_events_on_reading"
    add_index :ahoy_dashboard_alert_events, :fired_at
    add_index :ahoy_dashboard_alert_events, :check_id, where: "check_id IS NOT NULL",
              name: "index_ahoy_dashboard_alert_events_on_check"
    add_index :ahoy_dashboard_alert_events, :previous_check_id, where: "previous_check_id IS NOT NULL",
              name: "index_ahoy_dashboard_alert_events_on_previous_check"

    if table_exists?(CHECKS)
      add_foreign_key :ahoy_dashboard_alert_events, CHECKS, column: :check_id, on_delete: :nullify
      add_foreign_key :ahoy_dashboard_alert_events, CHECKS, column: :previous_check_id, on_delete: :nullify
    end

    create_table :ahoy_dashboard_alert_digests do |t|
      t.integer :period, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :status, null: false, default: 0
      t.integer :alerts_count, null: false, default: 0
      t.datetime :sent_at
      t.string :error
      t.timestamps
    end

    add_index :ahoy_dashboard_alert_digests, [ :period, :starts_on ], unique: true,
              name: "index_ahoy_dashboard_alert_digests_on_period"
  end

  def down
    drop_table :ahoy_dashboard_alert_digests
    drop_table :ahoy_dashboard_alert_events
    drop_table :ahoy_dashboard_alert_rules
  end
end
