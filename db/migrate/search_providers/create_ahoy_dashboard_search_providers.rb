class CreateAhoyDashboardSearchProviders < ActiveRecord::Migration[6.0]
  def change
    create_table :ahoy_dashboard_serp_providers do |t|
      t.string :name, null: false
      t.boolean :active, null: false, default: false
      t.text :credentials
      t.integer :monthly_cap_units, null: false, default: 500
      t.integer :units_spent, null: false, default: 0
      t.date :units_reset_on
      t.datetime :last_used_at
      t.string :last_error
      t.datetime :last_error_at
      t.timestamps
    end

    add_index :ahoy_dashboard_serp_providers, :name, unique: true
    add_index :ahoy_dashboard_serp_providers, :active, unique: true, where: "active",
              name: "index_ahoy_dashboard_serp_providers_on_one_active"

    create_table :ahoy_dashboard_serp_spend_days do |t|
      t.string :provider, null: false
      t.date :on, null: false
      t.integer :kind, null: false, default: 0
      t.integer :units, null: false, default: 0
      t.timestamps
    end

    add_index :ahoy_dashboard_serp_spend_days, [ :provider, :on, :kind ], unique: true,
              name: "index_ahoy_dashboard_serp_spend_days_on_day"
    add_index :ahoy_dashboard_serp_spend_days, :on
  end
end
