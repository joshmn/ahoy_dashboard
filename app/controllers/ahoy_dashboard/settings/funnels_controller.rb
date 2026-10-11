module AhoyDashboard
  module Settings
    class FunnelsController < AhoyDashboard::BaseController
      before_action :set_funnel, only: [ :edit, :update, :destroy ]

      helper_method :goals, :funnel_steps

      def index
        @funnels = AhoyDashboard::Funnel.ordered.includes(funnel_steps: :goal).to_a
        # Deleting asks in the row rather than in a dialog, so the thing being
        # deleted stays on screen while the question is answered. A parameter on
        # the index rather than a verb of its own, and the link works with the
        # JavaScript off because it is a page.
        @confirming = params[:confirm].presence
      end

      def new
        @form = AhoyDashboard::FunnelForm.new
      end

      def create
        @form = AhoyDashboard::FunnelForm.new(funnel_params)
        return redraw(:new) if removing? || adding?

        AhoyDashboard::Funnels::CreateCommand.call(form: @form) do
          on(:ok) { redirect_to settings_funnels_path, notice: "Funnel saved." }
          on(:invalid) { |form| rejected(form, :new) }
          on(:duplicate) { |form| rejected(form, :new) }
        end
      end

      def edit
        @form = AhoyDashboard::FunnelForm.from_record(@funnel)
      end

      # Both nudges are this funnel's own order and nothing else, one for where it
      # sits in the list and one for where a step sits inside it, so they are the
      # same update as any other edit rather than resources of their own.
      def update
        return move if nudge.present?
        return move_step if step_nudge.present?

        @form = AhoyDashboard::FunnelForm.new(funnel_params)
        return redraw(:edit) if removing? || adding?

        AhoyDashboard::Funnels::UpdateCommand.call(funnel: @funnel, form: @form) do
          on(:ok) { redirect_to settings_funnels_path, notice: "Funnel saved." }
          on(:invalid) { |form| rejected(form, :edit) }
          on(:duplicate) { |form| rejected(form, :edit) }
        end
      end

      def destroy
        AhoyDashboard::Funnels::DestroyCommand.call(funnel: @funnel) do
          on(:ok) { redirect_to settings_funnels_path, notice: "Funnel deleted." }
        end
      end

      private

      def set_funnel
        @funnel = AhoyDashboard::Funnel.find(params[:id])
      end

      def removing?
        params.dig(:funnel, :remove).present?
      end

      def adding?
        params.dig(:funnel, :add).present?
      end

      # Taking a step out redraws the form rather than saving it, so removing one
      # of two steps shows the step gone instead of answering with the minimum
      # steps error. Everything else typed into the form came along in the same
      # submit and survives. A 200 rather than a 422, because nothing was rejected.
      def redraw(template)
        @form = adding? ? @form.with_extra_slot : @form.without_slot(params.dig(:funnel, :remove))

        render template
      end

      def move
        AhoyDashboard::Funnels::MoveCommand.call(funnel: @funnel, direction: nudge) do
          on(:ok) { redirect_to settings_funnels_path }
          on(:nothing_to_do) { redirect_to settings_funnels_path }
        end
      end

      def move_step
        step_id, direction = step_nudge.to_s.split(":")

        AhoyDashboard::FunnelSteps::MoveCommand.call(funnel: @funnel, step_id: step_id, direction: direction) do
          on(:ok) { redirect_to edit_settings_funnel_path(@funnel) }
          on(:nothing_to_do) { redirect_to edit_settings_funnel_path(@funnel) }
        end
      end

      def rejected(form, template)
        @form = form
        render template, status: :unprocessable_entity
      end

      def nudge
        params.dig(:funnel, :nudge)
      end

      # A step's nudge names the step as well as the direction, because there is
      # one button per step on the screen rather than one for the funnel.
      def step_nudge
        params.dig(:funnel, :step_nudge)
      end

      def funnel_params
        params.require(:funnel).permit(*AhoyDashboard::FunnelForm::FIELDS, **AhoyDashboard::FunnelForm::STEPS_FIELD)
      end

      # Every goal, in the order the goals screen puts them, so a funnel is built
      # out of conversions that already have names.
      def goals
        @goals ||= AhoyDashboard::Goal.ordered.to_a
      end

      # The form has already read these steps on edit. Reuse those records and
      # batch their goal associations before the order table names each step;
      # the same helper also covers invalid submissions and add/remove redraws.
      def funnel_steps
        @funnel_steps ||= @funnel.funnel_steps.to_a.tap do |steps|
          AhoyDashboard::PreloadAssociationsService.call(records: steps, associations: :goal)
        end
      end
    end
  end
end
