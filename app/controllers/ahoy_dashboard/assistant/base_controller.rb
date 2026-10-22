# frozen_string_literal: true

module AhoyDashboard
  module Assistant
    class BaseController < AhoyDashboard::BaseController
      private

      def required_permission
        :assistant
      end
    end
  end
end
