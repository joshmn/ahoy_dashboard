class CreateAhoyDashboardSearchConsole < ActiveRecord::Migration[6.0]
  def change
    create_table :ahoy_dashboard_google_accounts do |t|
      t.string :email
      t.text :access_token
      t.text :refresh_token
      t.datetime :expires_at
      t.string :scope
      t.string :property_uri
      t.datetime :connected_at
      t.datetime :synced_at
      t.string :last_error
      t.datetime :last_error_at
      t.date :backfilled_to
      t.timestamps
    end

    create_table :ahoy_dashboard_search_console_rows do |t|
      t.date :date, null: false
      t.string :query, null: false
      t.string :page, null: false
      t.string :device, null: false, default: ""
      t.string :country, null: false, default: ""
      t.integer :clicks, null: false, default: 0
      t.integer :impressions, null: false, default: 0
      t.float :ctr, null: false, default: 0.0
      t.float :position, null: false, default: 0.0
      t.timestamps
    end

    add_index :ahoy_dashboard_search_console_rows, [ :date, :query, :page, :device, :country ], unique: true,
              name: "index_ahoy_dashboard_search_console_rows_on_grain"
    add_index :ahoy_dashboard_search_console_rows, :date
    add_index :ahoy_dashboard_search_console_rows, :query

    create_table :ahoy_dashboard_search_console_totals do |t|
      t.date :date, null: false
      t.string :device, null: false, default: ""
      t.string :country, null: false, default: ""
      t.integer :clicks, null: false, default: 0
      t.integer :impressions, null: false, default: 0
      t.float :ctr, null: false, default: 0.0
      t.float :position, null: false, default: 0.0
      t.timestamps
    end

    add_index :ahoy_dashboard_search_console_totals, [ :date, :device, :country ], unique: true,
              name: "index_ahoy_dashboard_search_console_totals_on_grain"

    create_table :ahoy_dashboard_search_console_keywords do |t|
      t.date :date, null: false
      t.string :query, null: false
      t.string :device, null: false, default: ""
      t.string :country, null: false, default: ""
      t.integer :clicks, null: false, default: 0
      t.integer :impressions, null: false, default: 0
      t.float :ctr, null: false, default: 0.0
      t.float :position, null: false, default: 0.0
      t.timestamps
    end

    add_index :ahoy_dashboard_search_console_keywords, [ :date, :query, :device, :country ], unique: true,
              name: "index_ahoy_dashboard_search_console_keywords_on_grain"

    add_index :ahoy_dashboard_search_console_keywords, [ :query, :date ],
              name: "index_ahoy_dashboard_search_console_keywords_on_series"

    create_table :ahoy_dashboard_search_console_days do |t|
      t.date :date, null: false
      t.datetime :scanned_at, null: false
      t.timestamps
    end

    add_index :ahoy_dashboard_search_console_days, :date, unique: true
  end
end
