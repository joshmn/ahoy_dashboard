module AhoyDashboard
  module Settings
    class PropertiesController < AhoyDashboard::BaseController
      def index
        @form = AhoyDashboard::PropertyForm.new
        load_list
      end

      def create
        @form = AhoyDashboard::PropertyForm.new(property_params)

        AhoyDashboard::Properties::CreateCommand.call(form: @form) do
          on(:ok) { |property| redirect_to settings_properties_path, notice: "Added #{property.key}." }
          on(:invalid) { |form| rejected(form) }
          on(:duplicate) { |form| rejected(form) }
        end
      end

      # A nudge and a show/hide are both this property's own attributes, so they
      # are the same update rather than two more resources.
      def update
        property = find_property

        return move(property) if nudge.present?

        AhoyDashboard::Properties::UpdateCommand.call(property: property, enabled: params.dig(:property, :enabled)) do
          on(:ok) { |updated| redirect_to settings_properties_path, notice: notice_for(updated) }
        end
      end

      def destroy
        property = find_property

        AhoyDashboard::Properties::DestroyCommand.call(property: property) do
          on(:ok) { |removed| redirect_to settings_properties_path, notice: "Took #{removed.key} off the list." }
        end
      end

      private

      def find_property
        AhoyDashboard::Property.find_by!(key: params[:key])
      end

      def move(property)
        AhoyDashboard::Properties::MoveCommand.call(property: property, direction: nudge) do
          on(:ok) { redirect_to settings_properties_path }
          on(:nothing_to_do) { redirect_to settings_properties_path }
        end
      end

      def nudge
        params.dig(:property, :nudge)
      end

      def notice_for(property)
        property.enabled? ? "Showing #{property.key} again." : "Hid #{property.key}."
      end

      def rejected(form)
        @form = form
        load_list
        render :index, status: :unprocessable_entity
      end

      def load_list
        @properties = AhoyDashboard::PropertyDecorator.wrap(AhoyDashboard::Property.ordered.to_a)
        @found = AhoyDashboard::PropertyKeysQuery.call(scope: query.scope) - @properties.map(&:key)
      end

      def property_params
        params.require(:property).permit(:key, :label)
      end
    end
  end
end
