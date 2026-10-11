module AhoyDashboard
  class Setting < AhoyDashboard::Record
    TIME_ZONE = "time_zone".freeze

    validates :key, presence: true, uniqueness: true

    class << self
      def read(key, default = nil)
        stored = where(key: key.to_s).pluck(:value).first

        stored.nil? ? default : stored
      rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
        default
      end

      def write(key, value)
        record = find_or_initialize_by(key: key.to_s)
        record.value = value
        record.save!
        record
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def clear(key)
        where(key: key.to_s).delete_all
      end
    end
  end
end
