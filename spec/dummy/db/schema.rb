# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `rails
# db:schema:load`. When creating a new database, `rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2026_10_10_153941) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "ahoy_dashboard_ai_visibility_answers", force: :cascade do |t|
    t.bigint "run_id", null: false
    t.bigint "prompt_id", null: false
    t.string "assistant", null: false
    t.string "model", null: false
    t.string "served_model"
    t.string "status", null: false
    t.string "error"
    t.text "text"
    t.boolean "mentioned", default: false, null: false
    t.boolean "cited", default: false, null: false
    t.integer "position"
    t.datetime "asked_at", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["asked_at", "assistant"], name: "index_ahoy_dashboard_ai_visibility_answers_on_asked_at"
    t.index ["prompt_id", "assistant", "model", "asked_at"], name: "index_ahoy_dashboard_ai_visibility_answers_on_prompt"
    t.index ["run_id", "prompt_id", "assistant", "model"], name: "index_ahoy_dashboard_ai_visibility_answers_once_per_run", unique: true
    t.index ["run_id"], name: "index_ahoy_dashboard_ai_visibility_answers_on_run"
  end

  create_table "ahoy_dashboard_ai_visibility_assistants", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "enabled", default: true, null: false
    t.string "models", default: [], null: false, array: true
    t.text "credentials"
    t.string "last_error"
    t.datetime "last_error_at"
    t.datetime "last_used_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["name"], name: "index_ahoy_dashboard_ai_visibility_assistants_on_name", unique: true
  end

  create_table "ahoy_dashboard_ai_visibility_prompts", force: :cascade do |t|
    t.text "text", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["text"], name: "index_ahoy_dashboard_ai_visibility_prompts_on_text", unique: true
  end

  create_table "ahoy_dashboard_ai_visibility_runs", force: :cascade do |t|
    t.string "status", null: false
    t.string "trigger", null: false
    t.integer "requests", default: 0, null: false
    t.string "skip_reason"
    t.datetime "started_at", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["started_at"], name: "index_ahoy_dashboard_ai_visibility_runs_on_started_at"
  end

  create_table "ahoy_dashboard_ai_visibility_sources", force: :cascade do |t|
    t.bigint "answer_id", null: false
    t.integer "slot", null: false
    t.text "url", null: false
    t.string "title"
    t.string "domain"
    t.boolean "ours", default: false, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["answer_id", "slot"], name: "index_ahoy_dashboard_ai_visibility_sources_on_slot", unique: true
    t.index ["domain"], name: "index_ahoy_dashboard_ai_visibility_sources_on_domain"
  end

  create_table "ahoy_dashboard_alert_digests", force: :cascade do |t|
    t.integer "period", null: false
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.integer "status", default: 0, null: false
    t.integer "alerts_count", default: 0, null: false
    t.datetime "sent_at"
    t.string "error"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["period", "starts_on"], name: "index_ahoy_dashboard_alert_digests_on_period", unique: true
  end

  create_table "ahoy_dashboard_alert_events", force: :cascade do |t|
    t.bigint "rule_id", null: false
    t.bigint "check_id"
    t.bigint "previous_check_id"
    t.datetime "fired_at", null: false
    t.integer "severity", default: 1, null: false
    t.string "headline", null: false
    t.string "detail"
    t.string "subject", null: false
    t.string "reading"
    t.boolean "sample_data", default: false, null: false
    t.datetime "cleared_at"
    t.datetime "delivered_at"
    t.string "delivery_error"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["check_id"], name: "index_ahoy_dashboard_alert_events_on_check", where: "(check_id IS NOT NULL)"
    t.index ["fired_at"], name: "index_ahoy_dashboard_alert_events_on_fired_at"
    t.index ["previous_check_id"], name: "index_ahoy_dashboard_alert_events_on_previous_check", where: "(previous_check_id IS NOT NULL)"
    t.index ["rule_id", "check_id"], name: "index_ahoy_dashboard_alert_events_on_saying", unique: true
    t.index ["rule_id", "subject", "reading"], name: "index_ahoy_dashboard_alert_events_on_reading", unique: true, where: "(reading IS NOT NULL)"
    t.index ["rule_id"], name: "index_ahoy_dashboard_alert_events_on_rule"
  end

  create_table "ahoy_dashboard_alert_rules", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.boolean "enabled", default: false, null: false
    t.integer "threshold"
    t.integer "floor"
    t.integer "severity", default: 1, null: false
    t.datetime "last_fired_at"
    t.datetime "last_checked_at"
    t.integer "fired_count", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["key"], name: "index_ahoy_dashboard_alert_rules_on_key", unique: true
  end

  create_table "ahoy_dashboard_annotations", force: :cascade do |t|
    t.datetime "happened_at", null: false
    t.string "label", null: false
    t.string "kind", default: "note", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["happened_at"], name: "index_ahoy_dashboard_annotations_on_happened_at"
  end

  create_table "ahoy_dashboard_assistant_providers", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "active", default: false, null: false
    t.text "credentials"
    t.string "model"
    t.string "api_base"
    t.decimal "temperature", precision: 3, scale: 2
    t.integer "max_tokens"
    t.datetime "last_used_at"
    t.string "last_error"
    t.datetime "last_error_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["active"], name: "index_ahoy_dashboard_assistant_providers_on_one_active", unique: true, where: "active"
    t.index ["name"], name: "index_ahoy_dashboard_assistant_providers_on_name", unique: true
  end

  create_table "ahoy_dashboard_backlink_anchors", force: :cascade do |t|
    t.string "text", null: false
    t.integer "links", default: 0, null: false
    t.integer "domains", default: 0, null: false
    t.date "seen_on", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["text"], name: "index_ahoy_dashboard_backlink_anchors_on_text", unique: true
  end

  create_table "ahoy_dashboard_backlink_domains", force: :cascade do |t|
    t.string "domain", null: false
    t.integer "authority"
    t.integer "links", default: 0, null: false
    t.boolean "follow", default: true, null: false
    t.string "kind"
    t.string "top_page"
    t.date "first_seen_on", null: false
    t.date "last_seen_on", null: false
    t.date "lost_on"
    t.string "provider", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["domain"], name: "index_ahoy_dashboard_backlink_domains_on_domain", unique: true
    t.index ["lost_on", "authority"], name: "index_ahoy_dashboard_backlink_domains_on_standing"
  end

  create_table "ahoy_dashboard_backlink_samples", force: :cascade do |t|
    t.date "on", null: false
    t.integer "domains", default: 0, null: false
    t.integer "links", default: 0, null: false
    t.integer "follow_domains", default: 0, null: false
    t.integer "gained", default: 0, null: false
    t.integer "lost", default: 0, null: false
    t.string "provider", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["on"], name: "index_ahoy_dashboard_backlink_samples_on_on", unique: true
  end

  create_table "ahoy_dashboard_chat_messages", force: :cascade do |t|
    t.bigint "chat_id", null: false
    t.integer "role", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.text "content"
    t.jsonb "tool_calls", default: [], null: false
    t.jsonb "views", default: [], null: false
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.string "error_message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.jsonb "reasoning"
    t.index ["chat_id", "created_at"], name: "index_ahoy_dashboard_chat_messages_on_thread"
    t.index ["chat_id"], name: "index_ahoy_dashboard_chat_messages_on_chat"
  end

  create_table "ahoy_dashboard_chats", force: :cascade do |t|
    t.string "title"
    t.string "model"
    t.string "provider"
    t.jsonb "context", default: {}, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "ahoy_dashboard_credentials", force: :cascade do |t|
    t.string "name", null: false
    t.text "secrets"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["name"], name: "index_ahoy_dashboard_credentials_on_name", unique: true
  end

  create_table "ahoy_dashboard_exclusions", force: :cascade do |t|
    t.string "name", null: false
    t.jsonb "filters", default: [], null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["name"], name: "index_ahoy_dashboard_exclusions_on_name", unique: true
  end

  create_table "ahoy_dashboard_funnel_steps", force: :cascade do |t|
    t.bigint "funnel_id", null: false
    t.bigint "goal_id", null: false
    t.integer "position", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["funnel_id", "goal_id"], name: "index_ahoy_dashboard_funnel_steps_on_funnel_id_and_goal_id", unique: true
    t.index ["funnel_id", "position"], name: "ahoy_dashboard_funnel_steps_on_slot", unique: true
    t.index ["goal_id"], name: "index_ahoy_dashboard_funnel_steps_on_goal_id"
  end

  create_table "ahoy_dashboard_funnels", force: :cascade do |t|
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["name"], name: "index_ahoy_dashboard_funnels_on_name", unique: true
    t.index ["position"], name: "index_ahoy_dashboard_funnels_on_position"
  end

  create_table "ahoy_dashboard_goals", force: :cascade do |t|
    t.integer "kind", default: 0, null: false
    t.string "event_name"
    t.string "path_pattern"
    t.string "display_name"
    t.string "property_key"
    t.string "property_value"
    t.string "currency"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index "COALESCE(\nCASE\n    WHEN ((display_name)::text ~ '[^[:space:]]'::text) THEN display_name\n    ELSE NULL::character varying\nEND,\nCASE\n    WHEN (kind = 1) THEN COALESCE(path_pattern, ''::character varying)\n    WHEN ((property_key)::text ~ '[^[:space:]]'::text) THEN (((((((COALESCE(event_name, ''::character varying))::text || ' ('::text) || (property_key)::text) || ': '::text) || (COALESCE(property_value, ''::character varying))::text) || ')'::text))::character varying\n    ELSE COALESCE(event_name, ''::character varying)\nEND)", name: "index_ahoy_dashboard_goals_on_effective_name", unique: true
    t.index "kind, ((event_name IS NULL)), COALESCE(event_name, ''::character varying), ((path_pattern IS NULL)), COALESCE(path_pattern, ''::character varying), ((property_key IS NULL)), COALESCE(property_key, ''::character varying), ((property_value IS NULL)), COALESCE(property_value, ''::character varying)", name: "index_ahoy_dashboard_goals_on_null_safe_definition", unique: true
    t.index ["position"], name: "index_ahoy_dashboard_goals_on_position"
  end

  create_table "ahoy_dashboard_google_accounts", force: :cascade do |t|
    t.string "email"
    t.text "access_token"
    t.text "refresh_token"
    t.datetime "expires_at"
    t.string "scope"
    t.string "property_uri"
    t.datetime "connected_at"
    t.datetime "synced_at"
    t.string "last_error"
    t.datetime "last_error_at"
    t.date "backfilled_to"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "ahoy_dashboard_job_run_entries", force: :cascade do |t|
    t.string "key", null: false
    t.integer "status", default: 0, null: false
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.text "error"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["key", "started_at"], name: "index_ahoy_dashboard_job_run_entries_on_key_and_started_at"
    t.index ["started_at"], name: "index_ahoy_dashboard_job_run_entries_on_started_at"
  end

  create_table "ahoy_dashboard_job_runs", force: :cascade do |t|
    t.string "key", null: false
    t.integer "status", default: 0, null: false
    t.datetime "last_run_at"
    t.datetime "last_finished_at"
    t.string "claim_token"
    t.datetime "claim_expires_at"
    t.string "last_error"
    t.integer "runs_count", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["key"], name: "index_ahoy_dashboard_job_runs_on_key", unique: true
  end

  create_table "ahoy_dashboard_keyword_ideas", force: :cascade do |t|
    t.string "seed", null: false
    t.string "query", null: false
    t.string "location", default: "us", null: false
    t.string "language", default: "en", null: false
    t.integer "volume"
    t.integer "difficulty"
    t.decimal "cpc", precision: 8, scale: 2
    t.decimal "competition", precision: 5, scale: 4
    t.string "intent"
    t.jsonb "trend", default: [], null: false
    t.string "provider", null: false
    t.datetime "fetched_at", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["seed", "fetched_at"], name: "index_ahoy_dashboard_keyword_ideas_on_seed"
    t.index ["seed", "query", "location", "language"], name: "index_ahoy_dashboard_keyword_ideas_on_grain", unique: true
  end

  create_table "ahoy_dashboard_page_groups", force: :cascade do |t|
    t.string "name", null: false
    t.jsonb "patterns", default: [], null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["name"], name: "index_ahoy_dashboard_page_groups_on_name", unique: true
    t.index ["position"], name: "index_ahoy_dashboard_page_groups_on_position"
  end

  create_table "ahoy_dashboard_places", force: :cascade do |t|
    t.bigint "code", null: false
    t.bigint "parent_code"
    t.string "name", null: false
    t.string "label", null: false
    t.string "country_code", limit: 2, null: false
    t.string "kind", null: false
    t.integer "depth", default: 0, null: false
    t.integer "children_count", default: 0, null: false
    t.datetime "synced_at", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index "lower((label)::text) text_pattern_ops", name: "index_ahoy_dashboard_places_on_label_prefix"
    t.index ["code"], name: "index_ahoy_dashboard_places_on_code", unique: true
    t.index ["country_code", "depth", "label"], name: "index_ahoy_dashboard_places_on_country"
    t.index ["parent_code", "depth", "label"], name: "index_ahoy_dashboard_places_on_children"
    t.index ["synced_at"], name: "index_ahoy_dashboard_places_on_synced_at"
  end

  create_table "ahoy_dashboard_properties", force: :cascade do |t|
    t.string "key", null: false
    t.string "label"
    t.integer "position", default: 0, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["enabled", "position"], name: "index_ahoy_dashboard_properties_on_enabled_and_position"
    t.index ["key"], name: "index_ahoy_dashboard_properties_on_key", unique: true
  end

  create_table "ahoy_dashboard_report_digests", force: :cascade do |t|
    t.integer "period", null: false
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.integer "status", default: 0, null: false
    t.integer "visitors_count", default: 0, null: false
    t.datetime "sent_at"
    t.string "error"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["period", "starts_on"], name: "index_ahoy_dashboard_report_digests_on_period", unique: true
  end

  create_table "ahoy_dashboard_saved_queries", force: :cascade do |t|
    t.string "name", null: false
    t.jsonb "params", default: {}, null: false
    t.boolean "pinned", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["name"], name: "index_ahoy_dashboard_saved_queries_on_name", unique: true
    t.index ["pinned", "position"], name: "index_ahoy_dashboard_saved_queries_on_pinned_and_position"
  end

  create_table "ahoy_dashboard_search_console_days", force: :cascade do |t|
    t.date "date", null: false
    t.datetime "scanned_at", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["date"], name: "index_ahoy_dashboard_search_console_days_on_date", unique: true
  end

  create_table "ahoy_dashboard_search_console_keywords", force: :cascade do |t|
    t.date "date", null: false
    t.string "query", null: false
    t.string "device", default: "", null: false
    t.string "country", default: "", null: false
    t.integer "clicks", default: 0, null: false
    t.integer "impressions", default: 0, null: false
    t.float "ctr", default: 0.0, null: false
    t.float "position", default: 0.0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["date", "query", "device", "country"], name: "index_ahoy_dashboard_search_console_keywords_on_grain", unique: true
    t.index ["query", "date"], name: "index_ahoy_dashboard_search_console_keywords_on_series"
  end

  create_table "ahoy_dashboard_search_console_rows", force: :cascade do |t|
    t.date "date", null: false
    t.string "query", null: false
    t.string "page", null: false
    t.string "device", default: "", null: false
    t.string "country", default: "", null: false
    t.integer "clicks", default: 0, null: false
    t.integer "impressions", default: 0, null: false
    t.float "ctr", default: 0.0, null: false
    t.float "position", default: 0.0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["date", "query", "page", "device", "country"], name: "index_ahoy_dashboard_search_console_rows_on_grain", unique: true
    t.index ["query"], name: "index_ahoy_dashboard_search_console_rows_on_query"
  end

  create_table "ahoy_dashboard_search_console_totals", force: :cascade do |t|
    t.date "date", null: false
    t.string "device", default: "", null: false
    t.string "country", default: "", null: false
    t.integer "clicks", default: 0, null: false
    t.integer "impressions", default: 0, null: false
    t.float "ctr", default: 0.0, null: false
    t.float "position", default: 0.0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["date", "device", "country"], name: "index_ahoy_dashboard_search_console_totals_on_grain", unique: true
  end

  create_table "ahoy_dashboard_segments", force: :cascade do |t|
    t.string "name", null: false
    t.jsonb "filters", default: [], null: false
    t.integer "position", default: 0, null: false
    t.boolean "applied_by_default", default: false, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["applied_by_default"], name: "index_ahoy_dashboard_segments_on_the_default", unique: true, where: "applied_by_default"
    t.index ["name"], name: "index_ahoy_dashboard_segments_on_name", unique: true
    t.index ["position"], name: "index_ahoy_dashboard_segments_on_position"
  end

  create_table "ahoy_dashboard_serp_ai_citations", force: :cascade do |t|
    t.bigint "run_id", null: false
    t.integer "slot", null: false
    t.string "link", null: false
    t.string "domain"
    t.string "title"
    t.datetime "checked_at", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["domain", "checked_at"], name: "index_ahoy_dashboard_serp_ai_citations_on_domain"
    t.index ["run_id", "slot"], name: "index_ahoy_dashboard_serp_ai_citations_on_slot", unique: true
    t.index ["run_id"], name: "index_ahoy_dashboard_serp_ai_citations_on_run"
  end

  create_table "ahoy_dashboard_serp_checks", force: :cascade do |t|
    t.bigint "run_id", null: false
    t.bigint "keyword_id", null: false
    t.bigint "target_id", null: false
    t.bigint "site_id", null: false
    t.datetime "checked_at", null: false
    t.string "location", null: false
    t.integer "position"
    t.integer "page"
    t.string "url"
    t.boolean "ai_overview_present"
    t.boolean "ai_overview_cited"
    t.integer "ai_overview_citation_position"
    t.integer "ai_overview_source_count"
    t.integer "status", default: 0, null: false
    t.string "error_message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["keyword_id"], name: "index_ahoy_dashboard_serp_checks_on_keyword"
    t.index ["run_id"], name: "index_ahoy_dashboard_serp_checks_on_run"
    t.index ["site_id", "checked_at"], name: "index_ahoy_dashboard_serp_checks_on_site_day"
    t.index ["site_id"], name: "index_ahoy_dashboard_serp_checks_on_site"
    t.index ["target_id", "location", "checked_at"], name: "index_ahoy_dashboard_serp_checks_on_series"
    t.index ["target_id", "run_id"], name: "index_ahoy_dashboard_serp_checks_on_target_run", unique: true
    t.index ["target_id"], name: "index_ahoy_dashboard_serp_checks_on_target"
  end

  create_table "ahoy_dashboard_serp_keyword_targets", force: :cascade do |t|
    t.bigint "keyword_id", null: false
    t.bigint "site_id", null: false
    t.boolean "tracking_enabled", default: true, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["keyword_id", "site_id"], name: "index_ahoy_dashboard_serp_keyword_targets_on_pair", unique: true
    t.index ["keyword_id"], name: "index_ahoy_dashboard_serp_keyword_targets_on_keyword"
    t.index ["site_id"], name: "index_ahoy_dashboard_serp_keyword_targets_on_site"
  end

  create_table "ahoy_dashboard_serp_keywords", force: :cascade do |t|
    t.string "query", null: false
    t.string "engine", default: "google", null: false
    t.string "device", default: "desktop", null: false
    t.string "language", default: "en", null: false
    t.jsonb "locations", default: ["us"], null: false
    t.integer "pages", default: 1, null: false
    t.integer "frequency", default: 0, null: false
    t.integer "source", default: 0, null: false
    t.boolean "enabled", default: true, null: false
    t.string "tags", default: [], null: false, array: true
    t.datetime "last_checked_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index "lower((query)::text), engine, device, language", name: "index_ahoy_dashboard_serp_keywords_on_folded_search", unique: true
    t.index ["enabled", "last_checked_at"], name: "index_ahoy_dashboard_serp_keywords_on_due"
    t.index ["query", "engine", "device", "language"], name: "index_ahoy_dashboard_serp_keywords_on_search", unique: true
    t.index ["tags"], name: "index_ahoy_dashboard_serp_keywords_on_tags", using: :gin
  end

  create_table "ahoy_dashboard_serp_providers", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "active", default: false, null: false
    t.text "credentials"
    t.integer "monthly_cap_units", default: 500, null: false
    t.integer "units_spent", default: 0, null: false
    t.date "units_reset_on"
    t.datetime "last_used_at"
    t.string "last_error"
    t.datetime "last_error_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["active"], name: "index_ahoy_dashboard_serp_providers_on_one_active", unique: true, where: "active"
    t.index ["name"], name: "index_ahoy_dashboard_serp_providers_on_name", unique: true
  end

  create_table "ahoy_dashboard_serp_results", force: :cascade do |t|
    t.bigint "run_id", null: false
    t.integer "position", null: false
    t.integer "page", default: 1, null: false
    t.string "link", null: false
    t.string "domain"
    t.string "title"
    t.datetime "checked_at", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["domain", "checked_at"], name: "index_ahoy_dashboard_serp_results_on_domain"
    t.index ["run_id", "position"], name: "index_ahoy_dashboard_serp_results_on_rank", unique: true
    t.index ["run_id"], name: "index_ahoy_dashboard_serp_results_on_run"
  end

  create_table "ahoy_dashboard_serp_run_pages", force: :cascade do |t|
    t.bigint "run_id", null: false
    t.integer "page_number", null: false
    t.integer "start", default: 0, null: false
    t.integer "depth", default: 10, null: false
    t.integer "status", default: 0, null: false
    t.string "provider_search_id"
    t.jsonb "request_params"
    t.jsonb "response"
    t.integer "raw_bytes"
    t.string "error_message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["run_id", "page_number"], name: "index_ahoy_dashboard_serp_run_pages_on_page", unique: true
    t.index ["run_id"], name: "index_ahoy_dashboard_serp_run_pages_on_run"
  end

  create_table "ahoy_dashboard_serp_runs", force: :cascade do |t|
    t.bigint "keyword_id", null: false
    t.string "provider", null: false
    t.string "engine", default: "google", null: false
    t.string "query", null: false
    t.string "location", null: false
    t.string "device", default: "desktop", null: false
    t.string "language", default: "en", null: false
    t.integer "requested_pages", default: 1, null: false
    t.integer "status", default: 0, null: false
    t.integer "cost_units", default: 0, null: false
    t.string "error_message"
    t.datetime "checked_at", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["checked_at"], name: "index_ahoy_dashboard_serp_runs_on_checked_at"
    t.index ["keyword_id", "location", "checked_at"], name: "index_ahoy_dashboard_serp_runs_on_series"
    t.index ["keyword_id"], name: "index_ahoy_dashboard_serp_runs_on_keyword"
    t.index ["query", "location", "checked_at"], name: "index_ahoy_dashboard_serp_runs_on_search"
  end

  create_table "ahoy_dashboard_serp_sites", force: :cascade do |t|
    t.string "name", null: false
    t.string "domain", null: false
    t.boolean "match_subdomains", default: false, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["domain"], name: "index_ahoy_dashboard_serp_sites_on_domain", unique: true
  end

  create_table "ahoy_dashboard_serp_spend_days", force: :cascade do |t|
    t.string "provider", null: false
    t.date "on", null: false
    t.integer "kind", default: 0, null: false
    t.integer "units", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["on"], name: "index_ahoy_dashboard_serp_spend_days_on_on"
    t.index ["provider", "on", "kind"], name: "index_ahoy_dashboard_serp_spend_days_on_day", unique: true
  end

  create_table "ahoy_dashboard_settings", force: :cascade do |t|
    t.string "key", null: false
    t.jsonb "value"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["key"], name: "index_ahoy_dashboard_settings_on_key", unique: true
  end

  create_table "ahoy_events", force: :cascade do |t|
    t.bigint "visit_id"
    t.bigint "user_id"
    t.string "name"
    t.jsonb "properties"
    t.datetime "time"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["properties"], name: "index_ahoy_events_on_properties", opclass: :jsonb_path_ops, using: :gin
    t.index ["time", "visit_id"], name: "index_ahoy_events_on_human_time_and_visit", where: "((properties ->> 'crawler'::text) IS NULL)"
    t.index ["time"], name: "index_ahoy_events_on_time"
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "visit_token"
    t.string "visitor_token"
    t.bigint "user_id"
    t.string "ip"
    t.text "user_agent"
    t.text "referrer"
    t.string "referring_domain"
    t.text "landing_page"
    t.string "browser"
    t.string "os"
    t.string "device_type"
    t.string "country"
    t.string "region"
    t.string "city"
    t.float "latitude"
    t.float "longitude"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_term"
    t.string "utm_content"
    t.string "utm_campaign"
    t.string "app_version"
    t.string "os_version"
    t.string "platform"
    t.string "asn"
    t.datetime "started_at"
    t.index ["started_at"], name: "index_ahoy_visits_on_started_at"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name", default: "", null: false
    t.boolean "admin", default: false, null: false
    t.datetime "confirmed_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "ahoy_dashboard_ai_visibility_answers", "ahoy_dashboard_ai_visibility_prompts", column: "prompt_id", on_delete: :cascade
  add_foreign_key "ahoy_dashboard_ai_visibility_answers", "ahoy_dashboard_ai_visibility_runs", column: "run_id", on_delete: :cascade
  add_foreign_key "ahoy_dashboard_ai_visibility_sources", "ahoy_dashboard_ai_visibility_answers", column: "answer_id", on_delete: :cascade
  add_foreign_key "ahoy_dashboard_alert_events", "ahoy_dashboard_alert_rules", column: "rule_id", on_delete: :cascade
  add_foreign_key "ahoy_dashboard_alert_events", "ahoy_dashboard_serp_checks", column: "check_id", on_delete: :nullify
  add_foreign_key "ahoy_dashboard_alert_events", "ahoy_dashboard_serp_checks", column: "previous_check_id", on_delete: :nullify
  add_foreign_key "ahoy_dashboard_chat_messages", "ahoy_dashboard_chats", column: "chat_id", on_delete: :cascade
  add_foreign_key "ahoy_dashboard_funnel_steps", "ahoy_dashboard_funnels", column: "funnel_id", on_delete: :cascade
  add_foreign_key "ahoy_dashboard_funnel_steps", "ahoy_dashboard_goals", column: "goal_id", on_delete: :restrict
  add_foreign_key "ahoy_dashboard_serp_ai_citations", "ahoy_dashboard_serp_runs", column: "run_id", on_delete: :cascade
  add_foreign_key "ahoy_dashboard_serp_checks", "ahoy_dashboard_serp_keyword_targets", column: "target_id", on_delete: :cascade
  add_foreign_key "ahoy_dashboard_serp_checks", "ahoy_dashboard_serp_keywords", column: "keyword_id", on_delete: :cascade
  add_foreign_key "ahoy_dashboard_serp_checks", "ahoy_dashboard_serp_runs", column: "run_id", on_delete: :cascade
  add_foreign_key "ahoy_dashboard_serp_checks", "ahoy_dashboard_serp_sites", column: "site_id", on_delete: :cascade
  add_foreign_key "ahoy_dashboard_serp_keyword_targets", "ahoy_dashboard_serp_keywords", column: "keyword_id", on_delete: :cascade
  add_foreign_key "ahoy_dashboard_serp_keyword_targets", "ahoy_dashboard_serp_sites", column: "site_id", on_delete: :cascade
  add_foreign_key "ahoy_dashboard_serp_results", "ahoy_dashboard_serp_runs", column: "run_id", on_delete: :cascade
  add_foreign_key "ahoy_dashboard_serp_run_pages", "ahoy_dashboard_serp_runs", column: "run_id", on_delete: :cascade
  add_foreign_key "ahoy_dashboard_serp_runs", "ahoy_dashboard_serp_keywords", column: "keyword_id", on_delete: :cascade
end
