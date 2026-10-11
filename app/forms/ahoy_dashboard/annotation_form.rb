module AhoyDashboard
  class AnnotationForm < AhoyDashboard::Form
    FIELDS = %i[label happened_at kind].freeze

    attribute :label, :string
    attribute :happened_at, :datetime
    attribute :kind, :string, default: AhoyDashboard::Annotation::DEFAULT_KIND

    validates :label, presence: true, length: { maximum: AhoyDashboard::Annotation::MAX_LABEL }
    validates :happened_at, presence: true
    validates :kind, inclusion: { in: AhoyDashboard::Annotation::KINDS.keys }

    def self.from_record(record)
      new(label: record.label, happened_at: record.local_time, kind: record.kind)
    end

    # The field posts a wall clock with no zone on the end of it, and the plain
    # datetime cast would read that as UTC. Every other time on the dashboard is
    # read in one zone, so this one is too.
    def happened_at=(value)
      super(value.is_a?(String) ? AhoyDashboard.time_zone.parse(value) : value)
    rescue ArgumentError
      super(nil)
    end

    def label
      super().to_s.strip.presence
    end

    def kind
      wanted = super().to_s
      AhoyDashboard::Annotation::KINDS.key?(wanted) ? wanted : AhoyDashboard::Annotation::DEFAULT_KIND
    end

    def record_attributes
      { label: label, happened_at: happened_at, kind: kind }
    end
  end
end
