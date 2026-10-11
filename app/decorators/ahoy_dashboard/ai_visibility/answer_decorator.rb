module AhoyDashboard
  module AiVisibility
    class AnswerDecorator < AhoyDashboard::Decorator
      def served_differently?
        served_model.present? && served_model != model
      end
    end
  end
end
