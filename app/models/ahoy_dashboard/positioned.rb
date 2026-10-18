module AhoyDashboard
  module Positioned
    extend ActiveSupport::Concern

    included do
      scope :ordered, -> { order(:position, :id) }
    end

    class_methods do
      def next_position
        (maximum(:position) || 0) + 1
      end
    end
  end
end
