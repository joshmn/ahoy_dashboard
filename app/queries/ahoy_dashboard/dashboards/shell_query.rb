# frozen_string_literal: true

module AhoyDashboard

  module Dashboards

    class ShellQuery
      class << self
        def call
          {
            reports: Report.grid_cards,
            funnels: Funnel.ordered.limit(Funnels::IndexQuery::PAGE_SIZE).to_a,
            funnel_count: Funnel.count,
            pinned: Installation.table?(SavedQuery.table_name) && SavedQuery.pinned.exists?
          }
        end
      end
    end
  end
end
