# frozen_string_literal: true

module AhoyDashboard

  class ReorderListService
    class << self
      def call(**options)
        new(**options).call
      end
    end

    def initialize(scope:, moved:, direction:)
      @scope = scope
      @moved = moved
      @direction = direction
    end

    def call
      scope.klass.transaction do
        ids = scope.reorder(:id).lock.pluck(:id)
        reordered = ReorderService.call(records: scope.where(id: ids).to_a, moved: moved, direction: direction)
        next if reordered.nil?

        reordered.each_with_index do |record, index|
          position = index + 1
          record.update_column(:position, position) if record.position != position
        end
        reordered
      end
    end

    private

    attr_reader :scope, :moved, :direction
  end
end
