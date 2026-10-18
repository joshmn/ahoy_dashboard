module AhoyDashboard
  class JourneysController < AhoyDashboard::BaseController
    def show
      @presenter = AhoyDashboard::JourneyPresenter.new(query: query, result: result)
    end

    private

    def result
      if params[:steps].blank? && params[:find].blank?
        snapshot = Dashboards::SnapshotReadQuery.call(query: query, section: :journey)
        return snapshot.journey if snapshot
      end

      AhoyDashboard::JourneyQuery.call(
        scope: query.scope,
        chain: params[:steps],
        searches: params[:find]
      )
    end
  end
end
