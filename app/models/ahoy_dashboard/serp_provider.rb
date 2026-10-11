module AhoyDashboard
  class SerpProvider < AhoyDashboard::Record
    NAMES = Serp::ADAPTERS.keys.map(&:to_s).freeze

    validates :name, presence: true, inclusion: { in: NAMES }, uniqueness: true
    validates :monthly_cap_units, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    scope :ordered, -> { order(:name) }

    def self.current
      find_by(active: true)
    end

    def self.for(name)
      find_by(name: name.to_s)
    end

    def adapter_class
      Serp.adapter_class(name)
    end

    def credentials
      SecretBox.read_values(value: self[:credentials], salt: SecretBox::SERP_SALT)
    end

    def credentials=(values)
      self[:credentials] = SecretBox.write_values(values: values, salt: SecretBox::SERP_SALT)
    end

    def credential(key)
      credentials[key.to_sym]
    end

    def credential_keys
      adapter_class.credential_keys
    end

    def ready?
      credential_keys.all? { |key| credential(key).present? }
    end

    def capped?
      monthly_cap_units.positive?
    end

    def spent_this_month(now: Time.current)
      month_of(now) == units_reset_on ? units_spent : 0
    end

    def remaining_units(now: Time.current)
      return Float::INFINITY unless capped?

      [ monthly_cap_units - spent_this_month(now: now), 0 ].max
    end

    def room_for?(units, now: Time.current)
      remaining_units(now: now) >= units.to_i
    end

    def reserve!(units, now: Time.current)
      units = units.to_i
      month = month_of(now)
      spent = spent_sql(month)

      claimed = self.class.where(id: id)
        .where("monthly_cap_units = 0 OR :units = 0 OR #{spent} + :units <= monthly_cap_units", units: units)
        .update_all([ "units_spent = #{spent} + ?, units_reset_on = ?, updated_at = ?", units, month, now ])

      refresh_spend
      claimed == 1
    end

    def record_spend!(units, now: Time.current, used: true)
      month = month_of(now)
      assignments = [ "units_spent = GREATEST(#{spent_sql(month)} + ?, 0), units_reset_on = ?, updated_at = ?",
                      units.to_i, month, now ]
      assignments = [ "#{assignments.first}, last_used_at = ?", *assignments.drop(1), now ] if used

      self.class.where(id: id).update_all(assignments)
      refresh_spend
    end

    def settle!(reserved, spent, now: Time.current, used: true)
      record_spend!(spent.to_i - reserved.to_i, now: now, used: used)
    end

    def record_error!(message)
      update_columns(last_error: message.to_s.first(255), last_error_at: Time.current)
    end

    def clear_error!
      return if last_error.blank?

      update_columns(last_error: nil, last_error_at: nil)
    end

    def activate!
      transaction do
        self.class.where.not(id: id).update_all(active: false)
        update!(active: true)
      end
    end

    def to_param
      name
    end

    private

    def month_of(now)
      now.in_time_zone(AhoyDashboard.time_zone).to_date.beginning_of_month
    end

    def spent_sql(month)
      self.class.sanitize_sql_array([ "(CASE WHEN units_reset_on = ? THEN units_spent ELSE 0 END)", month ])
    end

    def refresh_spend
      fresh = self.class.where(id: id).pick(:units_spent, :units_reset_on, :last_used_at, :updated_at)
      return if fresh.nil?

      %w[units_spent units_reset_on last_used_at updated_at].zip(fresh).each do |column, value|
        self[column] = value
        clear_attribute_change(column)
      end
    end
  end
end
