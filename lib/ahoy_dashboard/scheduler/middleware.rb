# frozen_string_literal: true

module AhoyDashboard
  class Scheduler
    class Middleware
      def initialize(app)
        @app = app
      end

      def call(env)
        AhoyDashboard.scheduler.start
        app.call(env)
      end

      private

      attr_reader :app
    end
  end
end
