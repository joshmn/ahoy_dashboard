module AhoyDashboard
  module Settings
    class SavedQueriesController < AhoyDashboard::Settings::BaseController
      before_action :set_record, only: [ :edit, :update, :destroy ]

      def index
        @records = AhoyDashboard::SavedQuery.listed
      end

      def new
        @form = AhoyDashboard::SavedQueryForm.new(params: AhoyDashboard::SavedQuery.clean(params[:question]))
      end

      def create
        @form = AhoyDashboard::SavedQueryForm.new(record_params)

        AhoyDashboard::Records::SaveCommand.call(record: AhoyDashboard::SavedQuery.new, form: @form, append: true) do
          on(:ok) { redirect_to settings_saved_queries_path, notice: "Question saved." }
          on(:invalid) { |form| rejected(form, :new) }
        end
      end

      def edit
        @form = AhoyDashboard::SavedQueryForm.from_record(@record)
        @changed = AhoyDashboard::SavedQuery.clean(params[:question])
        @form.params = @changed if @changed.present?
      end

      def update
        return move if nudge.present?

        @form = AhoyDashboard::SavedQueryForm.new(record_params)

        AhoyDashboard::Records::SaveCommand.call(record: @record, form: @form) do
          on(:ok) { redirect_to settings_saved_queries_path, notice: "Question saved." }
          on(:invalid) { |form| rejected(form) }
        end
      end

      def destroy
        AhoyDashboard::Records::DestroyCommand.call(record: @record) do
          on(:ok) { redirect_to settings_saved_queries_path, notice: "Question deleted." }
        end
      end

      private

      def set_record
        @record = AhoyDashboard::SavedQuery.find(params[:id])
      end

      def nudge
        params.dig(:saved_query, :nudge)
      end

      def move
        AhoyDashboard::Records::MoveCommand.call(record: @record, direction: nudge)
        redirect_to settings_saved_queries_path
      end

      def record_params
        params
          .require(:saved_query)
          .permit(*AhoyDashboard::SavedQueryForm::FIELDS, params: AhoyDashboard::SavedQuery::PERMITTED_PARAMS)
      end
    end
  end
end
