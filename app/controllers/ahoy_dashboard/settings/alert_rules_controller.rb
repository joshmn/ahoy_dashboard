module AhoyDashboard
  module Settings
    class AlertRulesController < AhoyDashboard::Settings::BaseController
      requires_installed :alerts

      before_action :set_rule, only: [ :edit, :update ]

      def index
        @groups = AhoyDashboard::Alerts::Catalogue.grouped(
          AhoyDashboard::AlertRuleDecorator.wrap(AhoyDashboard::AlertRule.where(key: AhoyDashboard::Alerts::Catalogue.keys).ordered.to_a)
        )
        @traffic_history = AhoyDashboard::Alerts::TrafficQuery.history?
      end

      def edit
      end

      def update
        AhoyDashboard::Alerts::Rules::UpdateCommand.call(rule: @rule, attributes: rule_params) do
          on(:ok) { redirect_to settings_alert_rules_path, notice: "Saved #{@rule.name}." }
          on(:refused) do |waiting_on|
            redirect_to edit_settings_alert_rule_path(@rule), alert: "#{@rule.name} cannot be switched on. #{waiting_on.detail}"
          end
          on(:invalid) { render :edit, status: 422 }
        end
      end

      private

      def set_rule
        @rule = AhoyDashboard::AlertRuleDecorator.new(AhoyDashboard::AlertRule.find(params[:id]))
      end

      def rule_params
        params.require(:alert_rule).permit(:enabled, :threshold, :floor, :severity)
      end
    end
  end
end
