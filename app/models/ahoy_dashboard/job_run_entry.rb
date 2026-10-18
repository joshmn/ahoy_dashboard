module AhoyDashboard
  class JobRunEntry < AhoyDashboard::Record
    KEEP = 100
    TRACE_LINES = 8

    enum :status, { running: 0, ok: 1, failed: 2 }, validate: true

    validates :key, :started_at, presence: true

    scope :recent, -> { order(started_at: :desc, id: :desc) }

    def self.ready?
      table_exists?
    rescue ActiveRecord::ActiveRecordError
      false
    end

    def self.open(key, now = Time.current)
      create!(key: key.to_s, status: :running, started_at: now)
    rescue ActiveRecord::ActiveRecordError
      nil
    end

    def self.prune(key)
      stale = where(key: key.to_s).recent.offset(KEEP).pluck(:id)
      where(id: stale).delete_all if stale.any?
    rescue ActiveRecord::ActiveRecordError
      nil
    end

    def finish!(now = Time.current)
      update_columns(status: self.class.statuses[:ok], finished_at: now, updated_at: now)
    end

    def fail!(error, now = Time.current)
      detail = [ "#{error.class}: #{error.message}", *Array(error.backtrace).first(TRACE_LINES) ].join("\n")

      update_columns(status: self.class.statuses[:failed], finished_at: now, error: detail, updated_at: now)
    end

    def duration
      finished_at && (finished_at - started_at)
    end

    def stuck?(now = Time.current)
      running? && started_at < now - JobRun::STUCK_AFTER
    end
  end
end
