module AhoyDashboard
  class JobRun < AhoyDashboard::Record
    STUCK_AFTER = 6.hours

    enum :status, { unknown: 0, running: 1, ok: 2, failed: 3, off: 4 }, validate: true

    validates :key, presence: true

    def self.for(key)
      find_or_create_by!(key: key.to_s)
    rescue ActiveRecord::RecordNotUnique
      find_by!(key: key.to_s)
    end

    def stuck?(now = Time.current)
      running? && last_run_at.present? && last_run_at < now - STUCK_AFTER
    end

    def switched_off!(now = Time.current)
      return if off?

      update_columns(status: self.class.statuses[:off], updated_at: now)
    end

    def to_param
      key
    end
  end
end
