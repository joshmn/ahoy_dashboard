module AhoyDashboard
  class AssistantProvider < AhoyDashboard::Record
    include StoredCredentials
    include LastError

    CREDENTIALS_SALT = SecretBox::ASSISTANT_SALT
    NAMES = Assistant::READERS.keys.freeze
    STORED_NAMES = (NAMES + Assistant::LEGACY_READERS.keys).freeze

    validates :name, presence: true, inclusion: { in: STORED_NAMES }, uniqueness: true

    normalizes :model, :api_base, with: ->(value) { value.to_s.strip.presence }

    validates :temperature, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2 }, allow_nil: true
    validates :max_tokens, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

    scope :ordered, -> { order(:name) }

    def self.current
      find_by(active: true)
    end

    def self.for(name)
      names = Assistant.stored_names(name)

      where(name: names).min_by { |provider| names.index(provider.name) }
    end

    def reader
      Assistant.reader_for(name)
    end

    def api_key
      credential(:api_key)
    end

    def model_name
      model.presence || reader.default_model
    end

    def endpoint
      api_base.presence || reader.api_base
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
