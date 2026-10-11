module AhoyDashboard
  # The saved questions somebody pinned, as cards under the chart.
  #
  # Its own resource and frame. Singular: there is one strip.
  class PinnedQuestionsController < AhoyDashboard::BaseController
    FRAME = "dash_pinned_questions".freeze

    def show
      snapshot = Dashboards::SnapshotReadQuery.call(query: query, section: :pinned)
      readings = snapshot ? snapshot.pinned_cards : AhoyDashboard::PinnedQuestionsQuery.call
      @cards = readings.map do |reading|
        AhoyDashboard::PinnedQuestionPresenter.new(reading: reading)
      end
    end
  end
end
