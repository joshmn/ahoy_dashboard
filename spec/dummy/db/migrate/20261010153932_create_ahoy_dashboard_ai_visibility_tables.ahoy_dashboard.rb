class CreateAhoyDashboardAiVisibilityTables < ActiveRecord::Migration[6.0]
  def change
    create_table :ahoy_dashboard_ai_visibility_assistants do |t|
      t.string :name, null: false
      t.boolean :enabled, null: false, default: true
      t.string :models, array: true, null: false, default: []
      t.text :credentials
      t.string :last_error
      t.datetime :last_error_at
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :ahoy_dashboard_ai_visibility_assistants, :name, unique: true,
              name: "index_ahoy_dashboard_ai_visibility_assistants_on_name"

    create_table :ahoy_dashboard_ai_visibility_prompts do |t|
      t.text :text, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :ahoy_dashboard_ai_visibility_prompts, :text, unique: true,
              name: "index_ahoy_dashboard_ai_visibility_prompts_on_text"

    create_table :ahoy_dashboard_ai_visibility_runs do |t|
      t.string :status, null: false
      t.string :trigger, null: false
      t.integer :requests, null: false, default: 0
      t.string :skip_reason
      t.datetime :started_at, null: false
      t.timestamps
    end

    add_index :ahoy_dashboard_ai_visibility_runs, :started_at,
              name: "index_ahoy_dashboard_ai_visibility_runs_on_started_at"

    create_table :ahoy_dashboard_ai_visibility_answers do |t|
      t.references :run, null: false, index: { name: "index_ahoy_dashboard_ai_visibility_answers_on_run" },
                          foreign_key: { to_table: :ahoy_dashboard_ai_visibility_runs, on_delete: :cascade }
      t.references :prompt, null: false, index: false,
                             foreign_key: { to_table: :ahoy_dashboard_ai_visibility_prompts, on_delete: :cascade }
      t.string :assistant, null: false
      t.string :model, null: false
      t.string :served_model
      t.string :status, null: false
      t.string :error
      t.text :text
      t.boolean :mentioned, null: false, default: false
      t.boolean :cited, null: false, default: false
      t.integer :position
      t.datetime :asked_at, null: false
      t.timestamps
    end

    add_index :ahoy_dashboard_ai_visibility_answers, [ :prompt_id, :assistant, :model, :asked_at ],
              name: "index_ahoy_dashboard_ai_visibility_answers_on_prompt"
    add_index :ahoy_dashboard_ai_visibility_answers, [ :asked_at, :assistant ],
              name: "index_ahoy_dashboard_ai_visibility_answers_on_asked_at"
    add_index :ahoy_dashboard_ai_visibility_answers, [ :run_id, :prompt_id, :assistant, :model ], unique: true,
              name: "index_ahoy_dashboard_ai_visibility_answers_once_per_run"

    create_table :ahoy_dashboard_ai_visibility_sources do |t|
      t.references :answer, null: false, index: false,
                             foreign_key: { to_table: :ahoy_dashboard_ai_visibility_answers, on_delete: :cascade }
      t.integer :slot, null: false
      t.text :url, null: false
      t.string :title
      t.string :domain
      t.boolean :ours, null: false, default: false
      t.timestamps
    end

    add_index :ahoy_dashboard_ai_visibility_sources, [ :answer_id, :slot ], unique: true,
              name: "index_ahoy_dashboard_ai_visibility_sources_on_slot"
    add_index :ahoy_dashboard_ai_visibility_sources, :domain,
              name: "index_ahoy_dashboard_ai_visibility_sources_on_domain"
  end
end
