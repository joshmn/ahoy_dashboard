module AhoyDashboard
  # What people did next. Its own resource rather than a report card, because it
  # reads sequences of events rather than a breakdown of one dimension, so it
  # answers none of the report machinery's questions.
  #
  # Everything it needs is in the URL, and every part of it arrives hand editable.
  # The query does the guarding: nothing in here is trusted on the way through.
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
