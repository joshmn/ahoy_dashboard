# frozen_string_literal: true

class CreateAhoyTables < ActiveRecord::Migration[6.0]
  def change
    create_table :ahoy_visits do |t|
      t.string :visit_token
      t.string :visitor_token
      t.bigint :user_id
      t.string :ip
      t.text :user_agent
      t.text :referrer
      t.string :referring_domain
      t.text :landing_page
      t.string :browser
      t.string :os
      t.string :device_type
      t.string :country
      t.string :region
      t.string :city
      t.float :latitude
      t.float :longitude
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_term
      t.string :utm_content
      t.string :utm_campaign
      t.string :app_version
      t.string :os_version
      t.string :platform
      t.string :asn
      t.datetime :started_at
    end

    add_index :ahoy_visits, :visit_token, unique: true
    add_index :ahoy_visits, :user_id
    add_index :ahoy_visits, :started_at

    create_table :ahoy_events do |t|
      t.bigint :visit_id
      t.bigint :user_id
      t.string :name
      t.jsonb :properties
      t.datetime :time
    end

    add_index :ahoy_events, [ :name, :time ]
    add_index :ahoy_events, :time
    add_index :ahoy_events, :user_id
    add_index :ahoy_events, :visit_id
    add_index :ahoy_events, :properties, using: :gin, opclass: :jsonb_path_ops
    add_index :ahoy_events, [ :time, :visit_id ], name: "index_ahoy_events_on_human_time_and_visit",
                                                  where: "((properties ->> 'crawler'::text) IS NULL)"
  end
end
