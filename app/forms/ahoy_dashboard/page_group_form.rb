module AhoyDashboard
  class PageGroupForm < AhoyDashboard::Form
    FIELDS = %i[name patterns].freeze

    attribute :name, TRIMMED
    attribute :patterns, :string

    validates :name, presence: true
    validate :has_a_pattern

    def self.from_record(record)
      new(name: record.name, patterns: record.pattern_list.join(", "))
    end

    def pattern_list
      AhoyDashboard::PageGroup.clean(patterns)
    end

    def record_attributes
      { name: name, patterns: pattern_list }
    end

    def add_duplicate_error
      errors.add(:name, "is already taken")
    end

    private

    def has_a_pattern
      return if pattern_list.any?

      errors.add(:patterns, "need at least one path, or the rule matches nothing")
    end
  end
end
