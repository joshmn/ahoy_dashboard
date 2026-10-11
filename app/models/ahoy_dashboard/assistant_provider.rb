module AhoyDashboard
  class AssistantProvider < AhoyDashboard::Record
    NAMES = Assistant::READERS.keys.freeze

    validates :name, presence: true, inclusion: { in: NAMES }, uniqueness: true

    normalizes :model, :api_base, with: ->(value) { value.to_s.strip.presence }

    validates :temperature, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2 }, allow_nil: true
    validates :max_tokens, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

    scope :ordered, -> { order(:name) }

    def self.current
      find_by(active: true)
    end

    def self.for(name)
      find_by(name: name.to_s)
    end

    def reader
      Assistant::READERS.fetch(name) { {} }
    end

    def provider
      reader[:provider]
    end

    def local?
      reader[:local].present?
    end

    def credentials
      SecretBox.read_values(value: self[:credentials], salt: SecretBox::ASSISTANT_SALT)
    end

    def credentials=(values)
      self[:credentials] = SecretBox.write_values(values: values, salt: SecretBox::ASSISTANT_SALT)
    end

    def credential(key)
      credentials[key.to_sym]
    end

    def api_key
      credential(:api_key)
    end

    def model_name
      model.presence || reader[:default_model]
    end

    def endpoint
      api_base.presence || reader[:api_base]
    end

    def ready?
      local? || api_key.present?
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
  end
end
