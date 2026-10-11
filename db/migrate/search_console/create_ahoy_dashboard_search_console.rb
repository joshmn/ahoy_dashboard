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
      # How far back the history walk has got. The nightly run only ever asks for
      # the last seven finished days, so without this the record starts the day
      # the job first ran and a trend has a week on it. Google serves sixteen
      # months and then those days are gone, so the walk goes and gets them.
      #
      # A watermark rather than a table of attempted days, because the walk is
      # strictly backwards and contiguous. A day that genuinely had no search
      # traffic writes no rows anywhere, so "have I already asked about this day"
      # cannot be answered by looking for its data.
      t.date :backfilled_to
      t.timestamps
    end

    # Not a hypertable, unlike the sample tables. Search Console revises the
    # last few days under you, so every run upserts a trailing window rather
    # than appending, and one site's sixteen months of query x page rows is
    # small enough that a plain table with the right indexes wins.
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

    # The authoritative per-day totals, fetched without the query dimension.
    # Google drops anonymized queries and truncates the tail by clicks, so
    # summing the rows above understates the real total and the gap is the
    # honest thing to report. This table is what any coverage figure divides by.
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

    # The third grain, and the one a trend is read from. The rows table keys on
    # query x page, which is where Google withholds the most and where a keyword
    # that moves between two pages reads as movement it did not make. This
    # table is the same days at query grain and nothing finer.
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

    # Query leading, because the read this table exists for is one keyword across
    # every day it appeared. The unique index above already covers the other
    # direction, so windowing a range does not need an index of its own.
    add_index :ahoy_dashboard_search_console_keywords, [ :query, :date ],
              name: "index_ahoy_dashboard_search_console_keywords_on_series"

    # One row per day Google has been asked about, whether or not it had
    # anything to say. The three grain tables record what came back, which
    # cannot answer whether a day was ever asked about: a day with no search
    # traffic writes no rows at any grain, so a quiet Sunday and a week the app
    # was down would look identical in them.
    create_table :ahoy_dashboard_search_console_days do |t|
      t.date :date, null: false
      t.datetime :scanned_at, null: false
      t.timestamps
    end

    add_index :ahoy_dashboard_search_console_days, :date, unique: true
  end
end
