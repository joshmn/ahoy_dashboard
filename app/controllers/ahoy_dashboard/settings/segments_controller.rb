module AhoyDashboard
  module Settings
    class SegmentsController < AhoyDashboard::Settings::BaseController
      before_action :set_segment, only: [ :edit, :update, :destroy ]

      def index
        @segments = AhoyDashboard::SegmentDecorator.wrap(AhoyDashboard::Segment.ordered.to_a)
      end

      def new
        @form = AhoyDashboard::SegmentForm.from_filters(AhoyDashboard::Filters.from_params(params))
      end

      def create
        @form = AhoyDashboard::SegmentForm.new(segment_params)
        return redraw(:new) if removing?

        AhoyDashboard::Records::SaveCommand.call(record: AhoyDashboard::Segment.new, form: @form, append: true) do
          on(:ok) { redirect_to settings_segments_path, notice: "Segment saved." }
          on(:invalid) { |form| rejected(form, :new) }
        end
      end

      def edit
        @form = AhoyDashboard::SegmentForm.from_record(@segment)
      end

      def update
        return move if nudge.present?

        @form = AhoyDashboard::SegmentForm.new(segment_params)
        return redraw(:edit) if removing?

        AhoyDashboard::Records::SaveCommand.call(record: @segment, form: @form) do
          on(:ok) { redirect_to settings_segments_path, notice: "Segment saved." }
          on(:invalid) { |form| rejected(form) }
        end
      end

      def destroy
        AhoyDashboard::Records::DestroyCommand.call(record: @segment) do
          on(:ok) { redirect_to settings_segments_path, notice: "Segment deleted." }
        end
      end

      private

      def set_segment
        @segment = AhoyDashboard::Segment.find(params[:id])
      end

      def removing?
        params.dig(:segment, :remove).present? || params.dig(:segment, :done).present?
      end

      def redraw(template)
        @form = @form.without_slot(params.dig(:segment, :remove))

        render template
      end

      def move
        AhoyDashboard::Records::MoveCommand.call(record: @segment, direction: nudge)
        redirect_to settings_segments_path
      end

      def nudge
        params.dig(:segment, :nudge)
      end

      def segment_params
        params.require(:segment).permit(*AhoyDashboard::SegmentForm::FIELDS, **AhoyDashboard::SegmentForm::FILTERS_FIELD)
      end
    end
  end
end
