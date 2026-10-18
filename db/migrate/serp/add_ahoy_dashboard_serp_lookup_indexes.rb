class AddAhoyDashboardSerpLookupIndexes < ActiveRecord::Migration[6.0]
  KEYWORDS = :ahoy_dashboard_serp_keywords
  RUNS = :ahoy_dashboard_serp_runs
  FOLDED = "index_ahoy_dashboard_serp_keywords_on_folded_search".freeze
  CHECKED = "index_ahoy_dashboard_serp_runs_on_checked_at".freeze

  def up
    unless index_name_exists?(KEYWORDS, FOLDED)
      ensure_unique!
      add_index KEYWORDS, "lower(query), engine, device, language", unique: true, name: FOLDED
    end
    add_index RUNS, :checked_at, name: CHECKED unless index_name_exists?(RUNS, CHECKED)
  end

  def down
    remove_index RUNS, name: CHECKED if index_name_exists?(RUNS, CHECKED)
    remove_index KEYWORDS, name: FOLDED if index_name_exists?(KEYWORDS, FOLDED)
  end

  private

  def ensure_unique!
    duplicates = select_values("SELECT array_agg(id ORDER BY id)::text FROM #{KEYWORDS} " \
                               "GROUP BY lower(query), engine, device, language HAVING count(*) > 1 LIMIT 10")
    return if duplicates.empty?

    raise ActiveRecord::MigrationError,
          "Tracked keywords differ only by capitals; keep one of each and delete the rest before retrying: " \
          "#{duplicates.join(", ")}"
  end
end
