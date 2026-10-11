module AhoyDashboard
  module Settings
    # Which rules are on and what each one's number is. Only those two: the
    # question a rule asks is code, and a screen that let somebody edit it would
    # be a rules engine nobody asked for.
    class AlertRulesController < AhoyDashboard::BaseController
      requires_installed :alerts

      before_action :set_section
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
        if @rule.waiting_on && ActiveModel::Type::Boolean.new.cast(rule_params[:enabled])
          redirect_to edit_settings_alert_rule_path(@rule), alert: "#{@rule.name} cannot be switched on. #{@rule.waiting_on.detail}"
        elsif @rule.update(rule_params)
          redirect_to settings_alert_rules_path, notice: "Saved #{@rule.name}."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def set_rule
        @rule = AhoyDashboard::AlertRuleDecorator.new(AhoyDashboard::AlertRule.find(params[:id]))
      end

      def rule_params
        params.require(:alert_rule).permit(:enabled, :threshold, :floor, :severity)
      end

      def set_section
        @dash_settings_section = "alert_rules"
      end
    end
  end
end
