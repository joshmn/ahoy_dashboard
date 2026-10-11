module AhoyDashboard
  module Settings
    class SavedQueriesController < AhoyDashboard::BaseController
      before_action :set_record, only: [ :edit, :update, :destroy ]

      def index
        @records = AhoyDashboard::SavedQuery.listed
        # Deleting asks in the row rather than in a dialog, so the thing being
        # deleted stays on screen while the question is answered.
        @confirming = params[:confirm].presence
      end

      def new
        @form = AhoyDashboard::SavedQueryForm.new(params: AhoyDashboard::SavedQuery.clean(params[:question]))
      end

      def create
        @form = AhoyDashboard::SavedQueryForm.new(record_params)

        AhoyDashboard::SavedQueries::CreateCommand.call(form: @form) do
          on(:ok) { redirect_to settings_saved_queries_path, notice: "Question saved." }
          on(:invalid) { |form| rejected(form, :new) }
          on(:duplicate) { |form| rejected(form, :new) }
        end
      end

      # A question changed in Explore comes back here with the new one in the
      # query string. Everything else about the record is unchanged, so the form
      # is the record with its question swapped rather than a second form.
      def edit
        @form = AhoyDashboard::SavedQueryForm.from_record(@record)
        @changed = AhoyDashboard::SavedQuery.clean(params[:question])
        @form.params = @changed if @changed.present?
      end

      def update
        return move if nudge.present?

        @form = AhoyDashboard::SavedQueryForm.new(record_params)

        AhoyDashboard::SavedQueries::UpdateCommand.call(record: @record, form: @form) do
          on(:ok) { redirect_to settings_saved_queries_path, notice: "Question saved." }
          on(:invalid) { |form| rejected(form, :edit) }
          on(:duplicate) { |form| rejected(form, :edit) }
        end
      end

      def destroy
        AhoyDashboard::SavedQueries::DestroyCommand.call(record: @record) do
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
        AhoyDashboard::SavedQueries::MoveCommand.call(record: @record, direction: nudge) do
          on(:ok) { redirect_to settings_saved_queries_path }
          on(:nothing_to_do) { redirect_to settings_saved_queries_path }
        end
      end

      def rejected(form, template)
        @form = form
        render template, status: :unprocessable_entity
      end

      # The question rides in as a nested hash of the same keys a URL carries.
      # Permitted by name rather than wholesale, and SavedQuery.clean drops
      # anything else on the way to the column.
      def record_params
        params
          .require(:saved_query)
          .permit(*AhoyDashboard::SavedQueryForm::FIELDS, params: AhoyDashboard::SavedQuery::PERMITTED_PARAMS)
      end
    end
  end
end
