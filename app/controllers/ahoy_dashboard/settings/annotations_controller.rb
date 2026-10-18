module AhoyDashboard
  module Settings
    class AnnotationsController < AhoyDashboard::Settings::BaseController
      before_action :set_record, only: [ :edit, :update, :destroy ]

      def index
        @records = AhoyDashboard::AnnotationDecorator.wrap(AhoyDashboard::Annotation.listed)
      end

      def new
        @form = AhoyDashboard::AnnotationForm.new(happened_at: Time.current.in_time_zone(AhoyDashboard.time_zone))
      end

      def create
        @form = AhoyDashboard::AnnotationForm.new(record_params)

        AhoyDashboard::Records::SaveCommand.call(record: AhoyDashboard::Annotation.new, form: @form) do
          on(:ok) { redirect_to settings_annotations_path, notice: "Annotation added." }
          on(:invalid) { |form| rejected(form, :new) }
        end
      end

      def edit
        @form = AhoyDashboard::AnnotationForm.from_record(@record)
      end

      def update
        @form = AhoyDashboard::AnnotationForm.new(record_params)

        AhoyDashboard::Records::SaveCommand.call(record: @record, form: @form) do
          on(:ok) { redirect_to settings_annotations_path, notice: "Annotation saved." }
          on(:invalid) { |form| rejected(form) }
        end
      end

      def destroy
        AhoyDashboard::Records::DestroyCommand.call(record: @record) do
          on(:ok) { redirect_to settings_annotations_path, notice: "Annotation deleted." }
        end
      end

      private

      def set_record
        @record = AhoyDashboard::Annotation.find(params[:id])
      end

      def record_params
        params.require(:annotation).permit(*AhoyDashboard::AnnotationForm::FIELDS)
      end
    end
  end
end
