module AhoyDashboard
  module Settings
    class PageGroupsController < AhoyDashboard::Settings::BaseController
      before_action :set_record, only: [ :edit, :update, :destroy ]

      def index
        @records = AhoyDashboard::PageGroup.listed
      end

      def new
        @form = AhoyDashboard::PageGroupForm.new
        set_preview
      end

      def create
        @form = AhoyDashboard::PageGroupForm.new(record_params)

        AhoyDashboard::Records::SaveCommand.call(record: AhoyDashboard::PageGroup.new, form: @form, append: true) do
          on(:ok) { redirect_to settings_page_groups_path, notice: "Rule added." }
          on(:invalid) { |form| rejected(form, :new) }
        end
      end

      def edit
        @form = AhoyDashboard::PageGroupForm.from_record(@record)
        set_preview
      end

      def update
        return move if nudge.present?

        @form = AhoyDashboard::PageGroupForm.new(record_params)

        AhoyDashboard::Records::SaveCommand.call(record: @record, form: @form) do
          on(:ok) { redirect_to settings_page_groups_path, notice: "Rule saved." }
          on(:invalid) { |form| rejected(form) }
        end
      end

      def destroy
        AhoyDashboard::Records::DestroyCommand.call(record: @record) do
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
        AhoyDashboard::Records::MoveCommand.call(record: @record, direction: nudge)
        redirect_to settings_page_groups_path
      end

      def rejected(form, template = :edit)
        @form = form
        set_preview
        super
      end

      def set_preview
        @preview = AhoyDashboard::Settings::PagePatternPreview.new(paths: recent_paths, patterns: @form.pattern_list)
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
