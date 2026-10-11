module AhoyDashboard
  module Settings
    class PageGroupsController < AhoyDashboard::BaseController
      before_action :set_record, only: [ :edit, :update, :destroy ]

      def index
        @records = AhoyDashboard::PageGroup.listed
        # Deleting asks in the row rather than in a dialog, so the thing being
        # deleted stays on screen while the question is answered.
        @confirming = params[:confirm].presence
      end

      def new
        @form = AhoyDashboard::PageGroupForm.new
        @paths = recent_paths
      end

      def create
        @form = AhoyDashboard::PageGroupForm.new(record_params)

        AhoyDashboard::PageGroups::CreateCommand.call(form: @form) do
          on(:ok) { redirect_to settings_page_groups_path, notice: "Rule added." }
          on(:invalid) { |form| rejected(form, :new) }
          on(:duplicate) { |form| rejected(form, :new) }
        end
      end

      def edit
        @form = AhoyDashboard::PageGroupForm.from_record(@record)
        @paths = recent_paths
      end

      def update
        return move if nudge.present?

        @form = AhoyDashboard::PageGroupForm.new(record_params)

        AhoyDashboard::PageGroups::UpdateCommand.call(record: @record, form: @form) do
          on(:ok) { redirect_to settings_page_groups_path, notice: "Rule saved." }
          on(:invalid) { |form| rejected(form, :edit) }
          on(:duplicate) { |form| rejected(form, :edit) }
        end
      end

      def destroy
        AhoyDashboard::PageGroups::DestroyCommand.call(record: @record) do
          on(:ok) { redirect_to settings_page_groups_path, notice: "Rule deleted." }
        end
      end

      private

      def set_record
        @record = AhoyDashboard::PageGroup.find(params[:id])
      end

      def nudge
        params.dig(:page_group, :nudge)
      end

      def move
        AhoyDashboard::PageGroups::MoveCommand.call(record: @record, direction: nudge) do
          on(:ok) { redirect_to settings_page_groups_path }
          on(:nothing_to_do) { redirect_to settings_page_groups_path }
        end
      end

      def rejected(form, template)
        @form = form
        @paths = recent_paths
        render template, status: :unprocessable_entity
      end

      def recent_paths
        AhoyDashboard::FilterOptionsQuery.call(
          scope: AhoyDashboard::QueryForm.from_params({ period: AhoyDashboard::QueryForm::DEFAULT_PERIOD, filters: nil }).scope,
          dimension: AhoyDashboard::Dimension.find_by_key("page"),
          limit: AhoyDashboard::Settings::PagePatternPreview::POOL,
          counted: true
        )
      rescue ActiveRecord::StatementInvalid
        []
      end

      def record_params
        params.require(:page_group).permit(*AhoyDashboard::PageGroupForm::FIELDS)
      end
    end
  end
end
