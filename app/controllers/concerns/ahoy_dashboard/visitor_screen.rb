module AhoyDashboard
  module VisitorScreen
    extend ActiveSupport::Concern

    private

    def render_journey(person)
      raise ActiveRecord::RecordNotFound if person.nil?

      result = AhoyDashboard::Visitors::JourneyQuery.call(
        person: person,
        page: params[:page],
        include_crawlers: query.include_crawlers?,
        include_internal: query.include_internal?
      )
      @presenter = AhoyDashboard::Visitors::JourneyPresenter.new(query: query, result: result, routes: self)

      render "ahoy_dashboard/visitors/show"
    end
  end
end
