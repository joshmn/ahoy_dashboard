module AhoyDashboard
  class JobRun < AhoyDashboard::Record
    STUCK_AFTER = 6.hours

    enum :status, { unknown: 0, running: 1, ok: 2, failed: 3, off: 4 }, validate: true

    validates :key, presence: true

    scope :ordered, -> { order(:key) }

    def self.for(key)
      find_or_create_by!(key: key.to_s)
    rescue ActiveRecord::RecordNotUnique
      find_by!(key: key.to_s)
    end

    # Wraps a job so it records its own outcome. Called from AhoyDashboard::Job
    # for every job that names a schedule key, which means a job run by the tick,
    # by a button, or by hand off a console all land in the same row. A key that
    # is nil is every other job in the gem and passes straight through.
    #
    # The row is looked up defensively because this sits in front of every job in
    # the suite: a host part way through installing the migration has jobs that
    # should still run, not jobs that raise on a missing table.
    def self.around(key, &block)
      row = key.present? ? lookup(key) : nil
      return block.call if row.nil?

      entry = JobRunEntry.open(key)
      result = block.call
      row.finished!
      entry&.finish!
      result
    rescue StandardError => e
      row&.broke!(e)
      entry&.fail!(e)
      raise
    ensure
      JobRunEntry.prune(key) if entry
    end

    def self.lookup(key)
      self.for(key)
    rescue ActiveRecord::ActiveRecordError
      nil
    end

    def self.start(key, now = Time.current)
      return if key.blank?

      row = lookup(key)
      row&.starting!(now)
      row
    rescue ActiveRecord::ActiveRecordError
      nil
    end

    def entry
      Schedule.find(key)
    end

    def ran?
      last_finished_at.present?
    end

    def stuck?(now = Time.current)
      running? && last_run_at.present? && last_run_at < now - STUCK_AFTER
    end

    def starting!(now = Time.current)
      update_columns(status: self.class.statuses[:running], last_run_at: now, last_error: nil,
                     runs_count: runs_count + 1, updated_at: now)
    end

    def finished!(now = Time.current)
      update_columns(status: self.class.statuses[:ok], last_finished_at: now, last_error: nil,
                     updated_at: now)
    end

    def broke!(error, now = Time.current)
      update_columns(status: self.class.statuses[:failed], last_finished_at: now,
                     last_error: "#{error.class}: #{error.message}".first(255), updated_at: now)
    end

    # Switched off is not a failure and must not clear what the last real run
    # said, so only the status moves.
    def switched_off!(now = Time.current)
      return if off?

      update_columns(status: self.class.statuses[:off], updated_at: now)
    end

    def to_param
      key
    end
  end
end
