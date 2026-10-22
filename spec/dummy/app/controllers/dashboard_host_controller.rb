# frozen_string_literal: true

class DashboardHostController < ApplicationController
  before_action :mark_host
  around_action :with_dashboard_site

  private

  def mark_host
    response.headers["X-Dashboard-Host"] = "present"
  end

  def with_dashboard_site
    return yield unless AhoyDashboard.config.context

    AhoyDashboard::Context.with(params[:site_id]) { yield }
  end
end
