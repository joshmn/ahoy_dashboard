class CreateAhoyDashboardPlaces < ActiveRecord::Migration[6.0]
  def change
    create_table :ahoy_dashboard_places do |t|
      t.bigint :code, null: false
      t.bigint :parent_code
      t.string :name, null: false
      t.string :label, null: false
      t.string :country_code, null: false, limit: 2
      t.string :kind, null: false
      t.integer :depth, null: false, default: 0
      t.integer :children_count, null: false, default: 0
      t.datetime :synced_at, null: false
      t.timestamps
    end

    add_index :ahoy_dashboard_places, :code, unique: true,
              name: "index_ahoy_dashboard_places_on_code"
    add_index :ahoy_dashboard_places, [ :parent_code, :depth, :label ],
              name: "index_ahoy_dashboard_places_on_children"
    add_index :ahoy_dashboard_places, [ :country_code, :depth, :label ],
              name: "index_ahoy_dashboard_places_on_country"
    add_index :ahoy_dashboard_places, :synced_at,
              name: "index_ahoy_dashboard_places_on_synced_at"

    add_index :ahoy_dashboard_places, "lower(label) text_pattern_ops",
              name: "index_ahoy_dashboard_places_on_label_prefix"
  end
end
