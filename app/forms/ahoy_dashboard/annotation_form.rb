module AhoyDashboard
  class AnnotationForm < AhoyDashboard::Form
    FIELDS = %i[label happened_at kind].freeze

    attribute :label, TRIMMED
    attribute :happened_at, :datetime
    attribute :kind, :string, default: AhoyDashboard::Annotation::DEFAULT_KIND

    validates :label, presence: true, length: { maximum: AhoyDashboard::Annotation::MAX_LABEL }
    validates :happened_at, presence: true

    def self.from_record(record)
      new(label: record.label, happened_at: record.local_time, kind: record.kind)
    end

    def happened_at=(value)
      super(value.is_a?(String) ? AhoyDashboard.time_zone.parse(value) : value)
    rescue ArgumentError
      super(nil)
    end

    def kind
      wanted = super().to_s
      AhoyDashboard::Annotation::KINDS.key?(wanted) ? wanted : AhoyDashboard::Annotation::DEFAULT_KIND
    end

    def record_attributes
      { label: label, happened_at: happened_at, kind: kind }
    end

    def add_duplicate_error
      errors.add(:label, "is already taken")
    end
  end
end
