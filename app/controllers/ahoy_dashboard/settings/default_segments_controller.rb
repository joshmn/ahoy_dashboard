module AhoyDashboard
  module Settings
    class DefaultSegmentsController < AhoyDashboard::Settings::BaseController
      def create
        AhoyDashboard::DefaultSegments::SaveCommand.call(filters: AhoyDashboard::Filters.from_params(params)) do
          on(:ok) { redirect_to back_to_the_view, notice: "Saved. The dashboard opens with these filters from now on." }
          on(:no_filters) { redirect_to back_to_the_view, alert: "Add a filter first. A default with no filters is no default." }
          on(:invalid) { redirect_to back_to_the_view, alert: "Those filters could not be saved as the default." }
        end
      end

      def destroy
        AhoyDashboard::DefaultSegments::ClearCommand.call do
          on(:ok) { redirect_to back_to_the_view, notice: "No default any more. The dashboard opens unfiltered." }
          on(:nothing_to_do) { redirect_to back_to_the_view }
        end
      end

      private

      def back_to_the_view
        helpers.dash_destination_path(params[:return], view_params)
      end

      def view_params
        carried = AhoyDashboard::FilterDestination.read(params.permit(*AhoyDashboard::FilterDestination::KEYS), prefixed: false)

        query.to_query.merge(carried)
      end
    end
  end
end
