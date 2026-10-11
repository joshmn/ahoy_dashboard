class CreateAhoyDashboardReportDigests < ActiveRecord::Migration[6.0]
  def change
    create_table :ahoy_dashboard_report_digests do |t|
      t.integer :period, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :status, null: false, default: 0
      t.integer :visitors_count, null: false, default: 0
      t.datetime :sent_at
      t.string :error
      t.timestamps
    end

    add_index :ahoy_dashboard_report_digests, [ :period, :starts_on ], unique: true,
              name: "index_ahoy_dashboard_report_digests_on_period"
  end
end
