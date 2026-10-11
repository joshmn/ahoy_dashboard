module AhoyDashboard
  module Settings
    class SegmentsController < AhoyDashboard::BaseController
      before_action :set_segment, only: [ :edit, :update, :destroy ]

      def index
        @segments = AhoyDashboard::SegmentDecorator.wrap(AhoyDashboard::Segment.ordered.to_a)
        # Deleting asks in the row rather than in a dialog, so the thing being
        # deleted stays on screen while the question is answered. A parameter on
        # the index rather than a verb of its own, and the link works with the
        # JavaScript off because it is a page.
        @confirming = params[:confirm].presence
      end

      # Prefilled from the filters in the URL, which is how the dashboard's own
      # menu offers to save what is already applied. No route of its own: the
      # filters travel in the query string in exactly the shape the dashboard
      # carries them.
      def new
        @form = AhoyDashboard::SegmentForm.from_filters(AhoyDashboard::Filters.from_params(params))
      end

      def create
        @form = AhoyDashboard::SegmentForm.new(segment_params)
        return redraw(:new) if removing?

        AhoyDashboard::Segments::CreateCommand.call(form: @form) do
          on(:ok) { redirect_to settings_segments_path, notice: "Segment saved." }
          on(:invalid) { |form| rejected(form, :new) }
          on(:duplicate) { |form| rejected(form, :new) }
        end
      end

      def edit
        @form = AhoyDashboard::SegmentForm.from_record(@segment)
      end

      # A nudge is this segment's own position and nothing else, so it is the same
      # update as any other edit rather than a resource of its own.
      def update
        return move if nudge.present?

        @form = AhoyDashboard::SegmentForm.new(segment_params)
        return redraw(:edit) if removing?

        AhoyDashboard::Segments::UpdateCommand.call(segment: @segment, form: @form) do
          on(:ok) { redirect_to settings_segments_path, notice: "Segment saved." }
          on(:invalid) { |form| rejected(form, :edit) }
          on(:duplicate) { |form| rejected(form, :edit) }
        end
      end

      def destroy
        AhoyDashboard::Segments::DestroyCommand.call(segment: @segment) do
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

      # Taking a filter out redraws the form rather than saving it, so removing
      # the only filter shows it gone instead of answering with the minimum
      # filters error. Everything else typed into the form came along in the same
      # submit and survives. A 200 rather than a 422, because nothing was rejected.
      def redraw(template)
        @form = @form.without_slot(params.dig(:segment, :remove))

        render template
      end

      def move
        AhoyDashboard::Segments::MoveCommand.call(segment: @segment, direction: nudge) do
          on(:ok) { redirect_to settings_segments_path }
          on(:nothing_to_do) { redirect_to settings_segments_path }
        end
      end

      def rejected(form, template)
        @form = form
        render template, status: :unprocessable_entity
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
