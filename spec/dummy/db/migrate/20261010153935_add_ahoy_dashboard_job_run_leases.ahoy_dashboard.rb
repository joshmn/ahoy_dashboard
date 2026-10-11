class AddAhoyDashboardJobRunLeases < ActiveRecord::Migration[6.0]
  def up
    add_column :ahoy_dashboard_job_runs, :claim_token, :string if !column_exists?(:ahoy_dashboard_job_runs, :claim_token)
    add_column :ahoy_dashboard_job_runs, :claim_expires_at, :datetime if !column_exists?(:ahoy_dashboard_job_runs, :claim_expires_at)
  end

  def down
    remove_column :ahoy_dashboard_job_runs, :claim_expires_at
    remove_column :ahoy_dashboard_job_runs, :claim_token
  end
end
