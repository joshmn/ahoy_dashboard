module AhoyDashboard
  # Move one record up or down a hand-ordered list.
  #
  # Position is only the order the list is read in, so a move is worked out
  # against the list as it is shown and then every row is renumbered. Swapping
  # the two position values on their own would do nothing on a list nobody has
  # ordered yet, where every row still sits at zero.
  #
  # Returns the reordered records, or nil when there is nowhere to go: the record
  # is not in the list, or it is already at the end it was asked to move toward.
  class ReorderService
    DIRECTIONS = %w[up down].freeze
    UP = "up".freeze

    def self.call(**options)
      new(**options).call
    end

    def initialize(records:, moved:, direction:)
      @records = Array(records)
      @moved = moved
      @direction = direction.to_s
    end

    def call
      return nil unless DIRECTIONS.include?(direction)

      current = records.index { |record| record.id == moved.id }
      return nil if current.nil?

      neighbour = direction == UP ? current - 1 : current + 1
      return nil if neighbour.negative? || neighbour >= records.size

      reordered = records.dup
      reordered[current], reordered[neighbour] = reordered[neighbour], reordered[current]
      reordered
    end

    private

    attr_reader :records, :moved, :direction
  end
end
