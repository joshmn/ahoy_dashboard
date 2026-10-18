module AhoyDashboard
  module Settings
    module Segments
      class DefaultsController < AhoyDashboard::Settings::BaseController
        before_action :set_segment

        def create
          AhoyDashboard::DefaultSegments::MakeCommand.call(segment: @segment) do
            on(:ok) { |made| redirect_to settings_segments_path, notice: "#{made.name} is the default now." }
            on(:unreadable) do
              redirect_to settings_segments_path, alert: "That segment has a filter the dashboard cannot read. Fix it first."
            end
          end
        end

        def destroy
          AhoyDashboard::DefaultSegments::ClearCommand.call(segment: @segment) do
            on(:ok) { redirect_to settings_segments_path, notice: "No default any more. The dashboard opens unfiltered." }
            on(:nothing_to_do) { redirect_to settings_segments_path }
          end
        end

        private

        def set_segment
          @segment = AhoyDashboard::Segment.find(params[:segment_id])
        end
      end
    end
  end
end
