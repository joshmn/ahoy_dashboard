module AhoyDashboard
  class Annotation < AhoyDashboard::Record
    KINDS = {
      "deploy" => "Deploy",
      "campaign" => "Campaign",
      "note" => "Note"
    }.freeze

    DEFAULT_KIND = "note".freeze
    MAX_LABEL = 120

    validates :label, presence: true, length: { maximum: MAX_LABEL }
    validates :happened_at, presence: true
    validates :kind, inclusion: { in: KINDS.keys }

    normalizes :label, with: ->(value) { value.to_s.strip.presence }
    normalizes :kind, with: ->(value) { KINDS.key?(value.to_s) ? value.to_s : DEFAULT_KIND }

    scope :recent, -> { order(happened_at: :desc, id: :desc) }
    scope :between, ->(from, to) { where(happened_at: from..to) }

    def self.listed
      return [] unless Installation.table?(table_name)

      recent.to_a
    end

    PER_BUCKET = 2
    BUCKETS = AhoyDashboard::Sql::Buckets::UNITS.keys.freeze

    def local_time
      happened_at&.in_time_zone(AhoyDashboard.time_zone)
    end
  end
end
