# frozen_string_literal: true

module AhoyDashboard

  module DashboardsHelper

    def dash_dashboard_cache_key(section, snapshot: nil)
      generation = if snapshot
        [snapshot.snapshot_key, snapshot.computed_at.iso8601(9)]
      elsif @presenter.respond_to?(:fragment_cache_key)
        @presenter.fragment_cache_key
      end
      ["ahoy_dashboard/dashboard", section, generation,
        request.base_url, request.script_name, I18n.locale, query.to_query]
    end
  end
end
