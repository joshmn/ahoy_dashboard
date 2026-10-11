class CreateAhoyDashboardSerp < ActiveRecord::Migration[6.0]
  def change
    create_table :ahoy_dashboard_serp_sites do |t|
      t.string :name, null: false
      t.string :domain, null: false
      t.boolean :match_subdomains, null: false, default: false
      t.timestamps
    end

    add_index :ahoy_dashboard_serp_sites, :domain, unique: true

    create_table :ahoy_dashboard_serp_keywords do |t|
      t.string :query, null: false
      t.string :engine, null: false, default: "google"
      t.string :device, null: false, default: "desktop"
      t.string :language, null: false, default: "en"
      t.jsonb :locations, null: false, default: [ "us" ]
      t.integer :pages, null: false, default: 1
      t.integer :frequency, null: false, default: 0
      t.integer :source, null: false, default: 0
      t.boolean :enabled, null: false, default: true
      t.string :tags, array: true, null: false, default: []
      t.datetime :last_checked_at
      t.timestamps
    end

    add_index :ahoy_dashboard_serp_keywords, [ :query, :engine, :device, :language ], unique: true,
              name: "index_ahoy_dashboard_serp_keywords_on_search"
    add_index :ahoy_dashboard_serp_keywords, [ :enabled, :last_checked_at ],
              name: "index_ahoy_dashboard_serp_keywords_on_due"
    add_index :ahoy_dashboard_serp_keywords, :tags, using: :gin,
              name: "index_ahoy_dashboard_serp_keywords_on_tags"

    create_table :ahoy_dashboard_serp_keyword_targets do |t|
      t.references :keyword, null: false,
                   foreign_key: { to_table: :ahoy_dashboard_serp_keywords, on_delete: :cascade },
                   index: { name: "index_ahoy_dashboard_serp_keyword_targets_on_keyword" }
      t.references :site, null: false,
                   foreign_key: { to_table: :ahoy_dashboard_serp_sites, on_delete: :cascade },
                   index: { name: "index_ahoy_dashboard_serp_keyword_targets_on_site" }
      t.boolean :tracking_enabled, null: false, default: true
      t.timestamps
    end

    add_index :ahoy_dashboard_serp_keyword_targets, [ :keyword_id, :site_id ], unique: true,
              name: "index_ahoy_dashboard_serp_keyword_targets_on_pair"

    create_table :ahoy_dashboard_serp_runs do |t|
      t.references :keyword, null: false,
                   foreign_key: { to_table: :ahoy_dashboard_serp_keywords, on_delete: :cascade },
                   index: { name: "index_ahoy_dashboard_serp_runs_on_keyword" }
      t.string :provider, null: false
      t.string :engine, null: false, default: "google"
      t.string :query, null: false
      t.string :location, null: false
      t.string :device, null: false, default: "desktop"
      t.string :language, null: false, default: "en"
      t.integer :requested_pages, null: false, default: 1
      t.integer :status, null: false, default: 0
      t.integer :cost_units, null: false, default: 0
      t.string :error_message
      t.datetime :checked_at, null: false
      t.timestamps
    end

    add_index :ahoy_dashboard_serp_runs, [ :keyword_id, :location, :checked_at ],
              name: "index_ahoy_dashboard_serp_runs_on_series"
    add_index :ahoy_dashboard_serp_runs, [ :query, :location, :checked_at ],
              name: "index_ahoy_dashboard_serp_runs_on_search"

    create_table :ahoy_dashboard_serp_run_pages do |t|
      t.references :run, null: false,
                   foreign_key: { to_table: :ahoy_dashboard_serp_runs, on_delete: :cascade },
                   index: { name: "index_ahoy_dashboard_serp_run_pages_on_run" }
      t.integer :page_number, null: false
      t.integer :start, null: false, default: 0
      t.integer :depth, null: false, default: 10
      t.integer :status, null: false, default: 0
      t.string :provider_search_id
      t.jsonb :request_params
      t.jsonb :response
      t.integer :raw_bytes
      t.string :error_message
      t.timestamps
    end

    add_index :ahoy_dashboard_serp_run_pages, [ :run_id, :page_number ], unique: true,
              name: "index_ahoy_dashboard_serp_run_pages_on_page"

    create_table :ahoy_dashboard_serp_checks do |t|
      t.references :run, null: false,
                   foreign_key: { to_table: :ahoy_dashboard_serp_runs, on_delete: :cascade },
                   index: { name: "index_ahoy_dashboard_serp_checks_on_run" }
      t.references :keyword, null: false,
                   foreign_key: { to_table: :ahoy_dashboard_serp_keywords, on_delete: :cascade },
                   index: { name: "index_ahoy_dashboard_serp_checks_on_keyword" }
      t.references :target, null: false,
                   foreign_key: { to_table: :ahoy_dashboard_serp_keyword_targets, on_delete: :cascade },
                   index: { name: "index_ahoy_dashboard_serp_checks_on_target" }
      t.references :site, null: false,
                   foreign_key: { to_table: :ahoy_dashboard_serp_sites, on_delete: :cascade },
                   index: { name: "index_ahoy_dashboard_serp_checks_on_site" }
      t.datetime :checked_at, null: false
      t.string :location, null: false
      t.integer :position
      t.integer :page
      t.string :url
      t.boolean :ai_overview_present
      t.boolean :ai_overview_cited
      t.integer :ai_overview_citation_position
      t.integer :ai_overview_source_count
      t.integer :status, null: false, default: 0
      t.string :error_message
      t.timestamps
    end

    add_index :ahoy_dashboard_serp_checks, [ :target_id, :run_id ], unique: true,
              name: "index_ahoy_dashboard_serp_checks_on_target_run"
    add_index :ahoy_dashboard_serp_checks, [ :target_id, :location, :checked_at ],
              name: "index_ahoy_dashboard_serp_checks_on_series"
    add_index :ahoy_dashboard_serp_checks, [ :site_id, :checked_at ],
              name: "index_ahoy_dashboard_serp_checks_on_site_day"

    create_table :ahoy_dashboard_serp_ai_citations do |t|
      t.references :run, null: false,
                   foreign_key: { to_table: :ahoy_dashboard_serp_runs, on_delete: :cascade },
                   index: { name: "index_ahoy_dashboard_serp_ai_citations_on_run" }
      t.integer :slot, null: false
      t.string :link, null: false
      t.string :domain
      t.string :title
      t.datetime :checked_at, null: false
      t.timestamps
    end

    add_index :ahoy_dashboard_serp_ai_citations, [ :run_id, :slot ], unique: true,
              name: "index_ahoy_dashboard_serp_ai_citations_on_slot"
    add_index :ahoy_dashboard_serp_ai_citations, [ :domain, :checked_at ],
              name: "index_ahoy_dashboard_serp_ai_citations_on_domain"

    create_table :ahoy_dashboard_serp_results do |t|
      t.references :run, null: false,
                   foreign_key: { to_table: :ahoy_dashboard_serp_runs, on_delete: :cascade },
                   index: { name: "index_ahoy_dashboard_serp_results_on_run" }
      t.integer :position, null: false
      t.integer :page, null: false, default: 1
      t.string :link, null: false
      t.string :domain
      t.string :title
      t.datetime :checked_at, null: false
      t.timestamps
    end

    add_index :ahoy_dashboard_serp_results, [ :run_id, :position ], unique: true,
              name: "index_ahoy_dashboard_serp_results_on_rank"
    add_index :ahoy_dashboard_serp_results, [ :domain, :checked_at ],
              name: "index_ahoy_dashboard_serp_results_on_domain"
  end
end
