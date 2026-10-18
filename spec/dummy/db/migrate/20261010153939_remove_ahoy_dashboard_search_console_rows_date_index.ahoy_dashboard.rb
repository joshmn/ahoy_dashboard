# This migration comes from ahoy_dashboard
class RemoveAhoyDashboardSearchConsoleRowsDateIndex < ActiveRecord::Migration[6.0]
  ROWS = :ahoy_dashboard_search_console_rows
  DATE = "index_ahoy_dashboard_search_console_rows_on_date".freeze
  GRAIN = "index_ahoy_dashboard_search_console_rows_on_grain".freeze

  def up
    return unless index_name_exists?(ROWS, GRAIN)

    remove_index ROWS, name: DATE if index_name_exists?(ROWS, DATE)
  end

  def down
    add_index ROWS, :date, name: DATE unless index_name_exists?(ROWS, DATE)
  end
end
