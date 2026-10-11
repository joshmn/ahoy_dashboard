module AhoyDashboard
  # Something that happened at a given moment, marked on the chart.
  #
  # The answer to "what happened on the 12th?". A deploy, a campaign, a post that
  # went somewhere. It reads nothing and changes nothing: it is a note beside the
  # line, and the only reason it is a record rather than a comment in a file is
  # that the person who wants it there is looking at the dashboard when they
  # think of it.
  #
  # It is a moment, kept and read in the dashboard's own zone. A day axis still
  # draws one flag on the day that holds it, an hourly one puts the two o'clock
  # deploy at two o'clock, and the tip says the time either way.
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

    # Guarded against a missing table so the dashboard still boots mid-migration.
    def self.listed
      recent.to_a
    rescue ActiveRecord::StatementInvalid
      []
    end

    # What the chart draws, keyed by the point it lands on, the same bucket the
    # series put it in. Capped per point, because two flags on one are already
    # unreadable and ten are a wall. The caller passes the chart's own grouping:
    # capped by the day on a weekly axis, a week of deploys stacked on one point.
    PER_BUCKET = 2
    BUCKETS = AhoyDashboard::Sql::Buckets::UNITS.keys.freeze

    def self.for_range(range, bucket: :day)
      ChartAnnotationsQuery.new(range: range, bucket: bucket).grouped
    end

    def local_time
      happened_at&.in_time_zone(AhoyDashboard.time_zone)
    end
  end
end
