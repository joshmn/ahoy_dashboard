module AhoyDashboard
  module Settings
    class FunnelsController < AhoyDashboard::Settings::BaseController
      before_action :set_funnel, only: [ :edit, :update, :destroy ]

      helper_method :goals, :funnel_steps

      def index
        @funnels = AhoyDashboard::Funnel.ordered.includes(funnel_steps: :goal).to_a
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
        end
      end

      def edit
        @form = AhoyDashboard::FunnelForm.from_record(@funnel)
      end

      def update
        return move if nudge.present?
        return move_step if step_nudge.present?

        @form = AhoyDashboard::FunnelForm.new(funnel_params)
        return redraw(:edit) if removing? || adding?

        AhoyDashboard::Funnels::UpdateCommand.call(funnel: @funnel, form: @form) do
          on(:ok) { redirect_to settings_funnels_path, notice: "Funnel saved." }
          on(:invalid) { |form| rejected(form) }
        end
      end

      def destroy
        AhoyDashboard::Records::DestroyCommand.call(record: @funnel) do
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

      def redraw(template)
        @form = adding? ? @form.with_extra_slot : @form.without_slot(params.dig(:funnel, :remove))

        render template
      end

      def move
        AhoyDashboard::Records::MoveCommand.call(record: @funnel, direction: nudge)
        redirect_to settings_funnels_path
      end

      def move_step
        step_id, direction = step_nudge.to_s.split(":")

        AhoyDashboard::FunnelSteps::MoveCommand.call(funnel: @funnel, step_id: step_id, direction: direction)
        redirect_to edit_settings_funnel_path(@funnel)
      end

      def nudge
        params.dig(:funnel, :nudge)
      end

      def step_nudge
        params.dig(:funnel, :step_nudge)
      end

      def funnel_params
        params.require(:funnel).permit(*AhoyDashboard::FunnelForm::FIELDS, **AhoyDashboard::FunnelForm::STEPS_FIELD)
      end

      def goals
        @goals ||= AhoyDashboard::Goal.ordered.to_a
      end

      def funnel_steps
        @funnel_steps ||= @funnel.funnel_steps.to_a.tap do |steps|
          AhoyDashboard::PreloadAssociationsService.call(records: steps, associations: :goal)
        end
      end
    end
  end
end
