class CreateAhoyDashboardBacklinks < ActiveRecord::Migration[6.0]
  def change
    # One row per referring domain, not per link. A site linking four hundred
    # times out of a footer is one relationship, and counting the links makes it
    # look like four hundred.
    #
    # lost_on rather than deleting the row: a domain that stops linking is the
    # single most useful thing this table holds, and a delete throws it away.
    create_table :ahoy_dashboard_backlink_domains do |t|
      t.string :domain, null: false
      t.integer :authority
      t.integer :links, null: false, default: 0
      t.boolean :follow, null: false, default: true
      t.string :kind
      t.string :top_page
      t.date :first_seen_on, null: false
      t.date :last_seen_on, null: false
      t.date :lost_on
      t.string :provider, null: false
      t.timestamps
    end

    add_index :ahoy_dashboard_backlink_domains, :domain, unique: true
    add_index :ahoy_dashboard_backlink_domains, [ :lost_on, :authority ],
              name: "index_ahoy_dashboard_backlink_domains_on_standing"

    # What the whole profile looked like on one day, so the count has a history
    # even though the rows above only ever hold the present.
    create_table :ahoy_dashboard_backlink_samples do |t|
      t.date :on, null: false
      t.integer :domains, null: false, default: 0
      t.integer :links, null: false, default: 0
      t.integer :follow_domains, null: false, default: 0
      t.integer :gained, null: false, default: 0
      t.integer :lost, null: false, default: 0
      t.string :provider, null: false
      t.timestamps
    end

    add_index :ahoy_dashboard_backlink_samples, :on, unique: true

    create_table :ahoy_dashboard_backlink_anchors do |t|
      t.string :text, null: false
      t.integer :links, null: false, default: 0
      t.integer :domains, null: false, default: 0
      t.date :seen_on, null: false
      t.timestamps
    end

    add_index :ahoy_dashboard_backlink_anchors, :text, unique: true
  end
end
