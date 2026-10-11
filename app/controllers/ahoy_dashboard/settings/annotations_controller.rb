module AhoyDashboard
  module Settings
    class AnnotationsController < AhoyDashboard::BaseController
      before_action :set_record, only: [ :edit, :update, :destroy ]

      def index
        @records = AhoyDashboard::AnnotationDecorator.wrap(AhoyDashboard::Annotation.listed)
        # Deleting asks in the row rather than in a dialog, so the thing being
        # deleted stays on screen while the question is answered.
        @confirming = params[:confirm].presence
      end

      def new
        @form = AhoyDashboard::AnnotationForm.new(happened_at: Time.current.in_time_zone(AhoyDashboard.time_zone))
      end

      def create
        @form = AhoyDashboard::AnnotationForm.new(record_params)

        AhoyDashboard::Annotations::CreateCommand.call(form: @form) do
          on(:ok) { redirect_to settings_annotations_path, notice: "Annotation added." }
          on(:invalid) { |form| rejected(form, :new) }
          on(:duplicate) { |form| rejected(form, :new) }
        end
      end

      def edit
        @form = AhoyDashboard::AnnotationForm.from_record(@record)
      end

      def update
        @form = AhoyDashboard::AnnotationForm.new(record_params)

        AhoyDashboard::Annotations::UpdateCommand.call(record: @record, form: @form) do
          on(:ok) { redirect_to settings_annotations_path, notice: "Annotation saved." }
          on(:invalid) { |form| rejected(form, :edit) }
          on(:duplicate) { |form| rejected(form, :edit) }
        end
      end

      def destroy
        AhoyDashboard::Annotations::DestroyCommand.call(record: @record) do
          on(:ok) { redirect_to settings_annotations_path, notice: "Annotation deleted." }
        end
      end

      private

      def set_record
        @record = AhoyDashboard::Annotation.find(params[:id])
      end

      def rejected(form, template)
        @form = form
        render template, status: :unprocessable_entity
      end

      def record_params
        params.require(:annotation).permit(*AhoyDashboard::AnnotationForm::FIELDS)
      end
    end
  end
end
