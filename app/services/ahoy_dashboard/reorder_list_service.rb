# frozen_string_literal: true

module AhoyDashboard

  class ReorderListService
    DIRECTIONS = %w[up down].freeze
    UP = "up"

    class << self
      def call(**options)
        new(**options).call
      end
    end

    def initialize(scope:, moved:, direction:, unique: false)
      @scope = scope
      @moved = moved
      @direction = direction.to_s
      @unique = unique
    end

    def call
      return nil unless DIRECTIONS.include?(direction)

      scope.klass.transaction do
        ids = scope.reorder(:id).lock.pluck(:id)
        reordered = swap(scope.where(id: ids).to_a)
        next if reordered.nil?

        renumber(reordered)
        reordered
      end
    end

    private

    attr_reader :scope, :moved, :direction, :unique

    def swap(records)
      current = records.index { |record| record.id == moved.id }
      return nil if current.nil?

      neighbour = direction == UP ? current - 1 : current + 1
      return nil if neighbour.negative? || neighbour >= records.size

      records[current], records[neighbour] = records[neighbour], records[current]
      records
    end

    def renumber(records)
      changed = records.each_with_index.reject { |record, index| record.position == index + 1 }

      if unique
        offset = records.map(&:position).max
        changed.each { |record, index| record.update_column(:position, offset + index + 1) }
      end

      changed.each { |record, index| record.update_column(:position, index + 1) }
    end
  end
end
