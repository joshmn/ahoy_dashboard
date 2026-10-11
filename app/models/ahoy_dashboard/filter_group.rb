module AhoyDashboard
  class FilterGroup
    include Enumerable

    # The operators whose values join as alternatives. "Country is US or CA" is
    # a question with an answer; "is not US or is not CA" matches nearly every
    # visit, so the negative ones stand as filters of their own instead.
    JOINING = %w[is contains].freeze

    attr_reader :to_a

    def initialize(filters)
      @to_a = Array(filters).uniq(&:to_param).freeze
    end

    def each(&block)
      to_a.each(&block)
    end

    def size
      to_a.size
    end

    def empty?
      to_a.empty?
    end

    def single?
      size == 1
    end

    def dimension
      to_a.first&.dimension
    end

    def add(filter)
      self.class.new(to_a + [ filter ])
    end

    def without(filter)
      self.class.new(to_a.reject { |candidate| candidate.equal?(filter) })
    end

    def kind
      return :session if any? { |filter| filter.dimension.key == AhoyDashboard::Dimension::GOAL_KEY }
      return :view if any? { |filter| filter.dimension.event? }
      return :exit if any?(&:exit?)

      :visit
    end

    def label
      return to_a.first.label if single?
      return to_a.map(&:label).join(" or ") unless uniform?

      first = to_a.first
      "#{first.dimension.filter_label} #{first.operator_label} #{to_a.map(&:value).join(' or ')}"
    end

    def uniform?
      to_a.map { |filter| [ filter.dimension.key, filter.operator ] }.uniq.one?
    end

    def negative_or?
      !single? && count(&:negative?) > 1
    end

    def to_param
      to_a.map(&:to_param)
    end
  end
end
