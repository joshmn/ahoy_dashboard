module AhoyDashboard
  # Who is on the site right now: the number in the header pill, and the page
  # behind it. Neither names its own window, so the count on load and the count
  # after the next refresh cannot be measured over different amounts of time.
  class RealtimeController < AhoyDashboard::BaseController
    def show
      respond_to do |format|
        format.html do
          @snapshot = AhoyDashboard::RealtimeQuery.snapshot
          @realtime = @snapshot.visitors
        end
        # Every dashboard page polls this every fifteen seconds, so it counts and
        # stops there rather than building the whole snapshot for one number.
        format.json { render json: { visitors: AhoyDashboard::RealtimeQuery.call } }
      end
    end
  end
end
