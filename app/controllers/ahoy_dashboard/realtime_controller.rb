module AhoyDashboard
  class RealtimeController < AhoyDashboard::BaseController
    FRAME = "dash_realtime_panel".freeze

    def show
      respond_to do |format|
        format.html do
          @snapshot = AhoyDashboard::RealtimeQuery.snapshot
          @realtime = @snapshot.visitors
        end
        format.json { render json: { visitors: AhoyDashboard::RealtimeQuery.call } }
      end
    end
  end
end
