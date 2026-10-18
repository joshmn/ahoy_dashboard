module AhoyDashboard
  module Settings
    class PropertiesController < AhoyDashboard::Settings::BaseController
      def index
        @form = AhoyDashboard::PropertyForm.new
        load_list
      end

      def create
        @form = AhoyDashboard::PropertyForm.new(property_params)

        AhoyDashboard::Records::SaveCommand.call(record: AhoyDashboard::Property.new, form: @form, append: true) do
          on(:ok) { |property| redirect_to settings_properties_path, notice: "Added #{property.key}." }
          on(:invalid) { |form| rejected(form) }
        end
      end

      def update
        property = find_property

        return move(property) if nudge.present?

        AhoyDashboard::Properties::UpdateCommand.call(property: property, enabled: params.dig(:property, :enabled)) do
          on(:ok) { |updated| redirect_to settings_properties_path, notice: notice_for(updated) }
        end
      end

      def destroy
        property = find_property

        AhoyDashboard::Records::DestroyCommand.call(record: property) do
          on(:ok) { |removed| redirect_to settings_properties_path, notice: "Took #{removed.key} off the list." }
        end
      end

      private

      def find_property
        AhoyDashboard::Property.find_by!(key: params[:key])
      end

      def move(property)
        AhoyDashboard::Records::MoveCommand.call(record: property, direction: nudge)
        redirect_to settings_properties_path
      end

      def nudge
        params.dig(:property, :nudge)
      end

      def notice_for(property)
        property.enabled? ? "Showing #{property.key} again." : "Hid #{property.key}."
      end

      def rejected(form, template = :index)
        load_list
        super
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
