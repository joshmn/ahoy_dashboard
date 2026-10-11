module AhoyDashboard
  module Assistant
    class Views
      LIMIT = 6

      def initialize
        @views = []
      end

      def push(view)
        accept(view)
        self
      end

      def accept(view)
        return :empty if view.nil? || !view.drawable?
        return :full if @views.size >= LIMIT

        @views << view
        :drawn
      end

      def any?
        @views.any?
      end

      def to_a
        @views.dup
      end

      def to_json_ready
        @views.map(&:to_h)
      end
    end
  end
end
