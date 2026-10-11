class CreateAhoyDashboardAssistant < ActiveRecord::Migration[6.0]
  def change
    create_table :ahoy_dashboard_chats do |t|
      t.string :title
      t.string :model
      t.string :provider
      t.jsonb :context, null: false, default: {}
      t.timestamps
    end

    create_table :ahoy_dashboard_chat_messages do |t|
      t.references :chat, null: false,
                   foreign_key: { to_table: :ahoy_dashboard_chats, on_delete: :cascade },
                   index: { name: "index_ahoy_dashboard_chat_messages_on_chat" }
      t.integer :role, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.text :content
      t.jsonb :tool_calls, null: false, default: []
      t.jsonb :views, null: false, default: []
      t.integer :input_tokens
      t.integer :output_tokens
      t.string :error_message
      t.timestamps
    end

    add_index :ahoy_dashboard_chat_messages, [ :chat_id, :created_at ],
              name: "index_ahoy_dashboard_chat_messages_on_thread"

    create_table :ahoy_dashboard_assistant_providers do |t|
      t.string :name, null: false
      t.boolean :active, null: false, default: false
      t.text :credentials
      t.string :model
      t.string :api_base
      t.decimal :temperature, precision: 3, scale: 2
      t.integer :max_tokens
      t.datetime :last_used_at
      t.string :last_error
      t.datetime :last_error_at
      t.timestamps
    end

    add_index :ahoy_dashboard_assistant_providers, :name, unique: true
    add_index :ahoy_dashboard_assistant_providers, :active, unique: true, where: "active",
              name: "index_ahoy_dashboard_assistant_providers_on_one_active"
  end
end
