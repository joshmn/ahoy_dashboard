module AhoyDashboard
  class PageGroupForm < AhoyDashboard::Form
    FIELDS = %i[name patterns].freeze

    attribute :name, :string
    attribute :patterns, :string

    validates :name, presence: true
    validate :has_a_pattern

    def self.from_record(record)
      new(name: record.name, patterns: record.pattern_list.join(", "))
    end

    def name
      super().to_s.strip.presence
    end

    # Typed as one comma separated line, stored as a list. The form keeps the
    # line because that is what somebody edits.
    def pattern_list
      AhoyDashboard::PageGroup.clean(patterns)
    end

    def record_attributes
      { name: name, patterns: pattern_list }
    end

    private

    def has_a_pattern
      return if pattern_list.any?

      errors.add(:patterns, "need at least one path, or the rule matches nothing")
    end
  end
end
