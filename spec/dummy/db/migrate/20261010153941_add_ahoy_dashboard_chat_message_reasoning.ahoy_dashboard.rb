# This migration comes from ahoy_dashboard
class AddAhoyDashboardChatMessageReasoning < ActiveRecord::Migration[6.0]
  def up
    return if column_exists?(:ahoy_dashboard_chat_messages, :reasoning)

    add_column :ahoy_dashboard_chat_messages, :reasoning, :jsonb
  end

  def down
    remove_column :ahoy_dashboard_chat_messages, :reasoning
  end
end
