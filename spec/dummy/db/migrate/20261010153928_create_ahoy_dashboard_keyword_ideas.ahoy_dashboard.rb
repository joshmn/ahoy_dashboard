class CreateAhoyDashboardKeywordIdeas < ActiveRecord::Migration[6.0]
  def change
    # Bought data, cached. Every row costs money to fetch, so a seed is fetched
    # once and read as often as anybody likes, and re-fetching is a deliberate
    # act rather than a page load.
    create_table :ahoy_dashboard_keyword_ideas do |t|
      t.string :seed, null: false
      t.string :query, null: false
      t.string :location, null: false, default: "us"
      t.string :language, null: false, default: "en"
      t.integer :volume
      t.integer :difficulty
      t.decimal :cpc, precision: 8, scale: 2
      t.decimal :competition, precision: 5, scale: 4
      t.string :intent
      t.jsonb :trend, null: false, default: []
      t.string :provider, null: false
      t.datetime :fetched_at, null: false
      t.timestamps
    end

    add_index :ahoy_dashboard_keyword_ideas, [ :seed, :query, :location, :language ], unique: true,
              name: "index_ahoy_dashboard_keyword_ideas_on_grain"
    add_index :ahoy_dashboard_keyword_ideas, [ :seed, :fetched_at ],
              name: "index_ahoy_dashboard_keyword_ideas_on_seed"
  end
end
