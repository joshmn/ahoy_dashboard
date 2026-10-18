module AhoyDashboard
  module AiVisibility
    class Assistant < AhoyDashboard::Record
      include StoredCredentials
      include LastError

      CREDENTIALS_SALT = SecretBox::AI_VISIBILITY_SALT
      MODEL_FORMAT = %r{\A[A-Za-z0-9][A-Za-z0-9._:/@-]*\z}
      MODEL_LENGTH = 100

      validates :name, presence: true, inclusion: { in: AiVisibility::NAMES }, uniqueness: true
      validates :models, length: { maximum: AiVisibility::MAX_MODELS,
                                   message: "can hold at most #{AiVisibility::MAX_MODELS} models" }
      validate :models_are_names

      normalizes :models, with: ->(values) { Array(values).map { |value| value.to_s.strip }.reject(&:blank?).uniq }

      def self.for(name)
        find_by(name: name.to_s)
      end

      def api_key
        credential(:api_key)
      end

      def record_success!(now: Time.current)
        update_columns(last_error: nil, last_error_at: nil, last_used_at: now)
      end

      def to_param
        name
      end

      private

      def models_are_names
        bad = models.reject { |model| model.length <= MODEL_LENGTH && model.match?(MODEL_FORMAT) }
        return if bad.empty?

        errors.add(:models, "#{bad.to_sentence} #{bad.one? ? "is not a model name" : "are not model names"}")
      end
    end
  end
end
