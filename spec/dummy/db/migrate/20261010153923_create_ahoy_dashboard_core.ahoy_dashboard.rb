class CreateAhoyDashboardCore < ActiveRecord::Migration[6.0]
  def change
    create_table :ahoy_dashboard_goals do |t|
      t.integer :kind, null: false, default: 0
      t.string :event_name
      t.string :path_pattern
      t.string :display_name
      t.string :property_key
      t.string :property_value
      t.string :currency
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    definition = ["kind", *%w[event_name path_pattern property_key property_value].flat_map do |column|
      ["(#{column} IS NULL)", "COALESCE(#{column}, '')"]
    end].join(", ")
    add_index :ahoy_dashboard_goals, definition, unique: true,
              name: "index_ahoy_dashboard_goals_on_null_safe_definition"
    name = <<~SQL.squish
      (COALESCE(CASE WHEN display_name ~ '[^[:space:]]' THEN display_name ELSE NULL END,
        CASE WHEN kind = 1 THEN COALESCE(path_pattern, '')
          WHEN property_key ~ '[^[:space:]]' THEN
            COALESCE(event_name, '') || ' (' || property_key || ': ' || COALESCE(property_value, '') || ')'
          ELSE COALESCE(event_name, '') END))
    SQL
    add_index :ahoy_dashboard_goals, name, unique: true, name: "index_ahoy_dashboard_goals_on_effective_name"
    add_index :ahoy_dashboard_goals, :position

    create_table :ahoy_dashboard_properties do |t|
      t.string :key, null: false
      t.string :label
      t.integer :position, null: false, default: 0
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end

    add_index :ahoy_dashboard_properties, :key, unique: true
    add_index :ahoy_dashboard_properties, [ :enabled, :position ]

    create_table :ahoy_dashboard_funnels do |t|
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :ahoy_dashboard_funnels, :name, unique: true
    add_index :ahoy_dashboard_funnels, :position

    create_table :ahoy_dashboard_funnel_steps do |t|
      t.references :funnel, null: false, index: false,
                   foreign_key: { to_table: :ahoy_dashboard_funnels, on_delete: :cascade }
      # Restrict rather than cascade. A funnel that quietly loses a step still
      # renders and still reports numbers, and they answer a different question
      # from the one somebody set up. Refusing the delete is the only version
      # that cannot silently change what a funnel means.
      t.references :goal, null: false,
                   foreign_key: { to_table: :ahoy_dashboard_goals, on_delete: :restrict }
      t.integer :position, null: false
      t.timestamps
    end

    add_index :ahoy_dashboard_funnel_steps, [ :funnel_id, :goal_id ], unique: true

    add_index :ahoy_dashboard_funnel_steps, [:funnel_id, :position], unique: true,
              name: "ahoy_dashboard_funnel_steps_on_slot"

    create_table :ahoy_dashboard_segments do |t|
      t.string :name, null: false
      # jsonb, because the value stored is already what AhoyDashboard::Filters#to_param
      # hands back: an array of dimension, operator and value hashes. Postgres
      # gives that array straight back with no Rails-side serializer in the way,
      # so the saved row, the query string a link carries and the filter objects
      # are all one shape. Same arrangement ahoy_events.properties has used all
      # along. Text plus a serializer would make the column unreadable to
      # anything but this app and turn a hand-edited row into a parse error.
      t.jsonb :filters, null: false, default: []
      t.integer :position, null: false, default: 0
      t.boolean :applied_by_default, null: false, default: false
      t.timestamps
    end

    add_index :ahoy_dashboard_segments, :name, unique: true
    add_index :ahoy_dashboard_segments, :position
    add_index :ahoy_dashboard_segments, :applied_by_default, unique: true, where: "applied_by_default",
              name: "index_ahoy_dashboard_segments_on_the_default"

    create_table :ahoy_dashboard_saved_queries do |t|
      t.string :name, null: false
      # The whole question, in the shape the URL carries it, so opening one is
      # the same navigation as editing the address bar and nothing has to know
      # how to rebuild an explore from parts.
      t.jsonb :params, null: false, default: {}
      t.boolean :pinned, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :ahoy_dashboard_saved_queries, :name, unique: true
    add_index :ahoy_dashboard_saved_queries, [ :pinned, :position ]

    create_table :ahoy_dashboard_page_groups do |t|
      t.string :name, null: false
      # One rule can name several paths, so the patterns are a list. First
      # matching rule wins, which is what position orders.
      t.jsonb :patterns, null: false, default: []
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :ahoy_dashboard_page_groups, :name, unique: true
    add_index :ahoy_dashboard_page_groups, :position

    create_table :ahoy_dashboard_annotations do |t|
      t.datetime :happened_at, null: false
      t.string :label, null: false
      t.string :kind, null: false, default: "note"
      t.timestamps
    end

    add_index :ahoy_dashboard_annotations, :happened_at

    create_table :ahoy_dashboard_exclusions do |t|
      t.string :name, null: false
      t.jsonb :filters, null: false, default: []
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end

    add_index :ahoy_dashboard_exclusions, :name, unique: true

    # One generic table for a named secret that is only ever "a handful of
    # key/value pairs" and does not carry other columns alongside it. Serp and
    # assistant providers keep their own credentials column because they carry
    # caps, spend and an active flag too; anything smaller than that belongs
    # here instead of a bespoke migration and model per integration.
    create_table :ahoy_dashboard_credentials do |t|
      t.string :name, null: false
      t.text :secrets
      t.timestamps
    end

    add_index :ahoy_dashboard_credentials, :name, unique: true

    create_table :ahoy_dashboard_settings do |t|
      t.string :key, null: false
      t.jsonb :value
      t.timestamps
    end

    add_index :ahoy_dashboard_settings, :key, unique: true

    # When each scheduled thing last ran, and how it went. The schedule itself is
    # a registry in code; this is the one part of it that has to survive a
    # restart, because a tick that cannot remember either re-runs everything
    # every time or never runs anything at all.
    #
    # It is also the answer to the question the manual buttons exist for: stale
    # because nothing is scheduled, or stale because the last run failed.
    create_table :ahoy_dashboard_job_runs do |t|
      t.string :key, null: false
      t.integer :status, null: false, default: 0
      t.datetime :last_run_at
      t.datetime :last_finished_at
      t.string :claim_token
      t.datetime :claim_expires_at
      t.string :last_error
      t.integer :runs_count, null: false, default: 0
      t.timestamps
    end

    add_index :ahoy_dashboard_job_runs, :key, unique: true

    create_table :ahoy_dashboard_job_run_entries do |t|
      t.string :key, null: false
      t.integer :status, null: false, default: 0
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.text :error
      t.timestamps
    end

    add_index :ahoy_dashboard_job_run_entries, [ :key, :started_at ]
    add_index :ahoy_dashboard_job_run_entries, :started_at
  end
end
