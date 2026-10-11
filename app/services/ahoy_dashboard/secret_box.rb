module AhoyDashboard
  # Envelope encryption for the secrets this subsystem holds: the two Google
  # tokens, a search provider's api credentials, and anything stored through
  # AhoyDashboard::Credential. One salt per purpose, so a value written for one
  # cannot be read back by the other.
  #
  # ActiveRecord::Encryption is not set up in this app and turning it on is a
  # global change with a key-management story attached, which is a lot to take
  # on for one row in one table. A refresh token is still the one secret here
  # that would otherwise sit in plain text in a database dump, so it gets its
  # own envelope keyed off secret_key_base instead.
  #
  # Consequence worth knowing: rotating secret_key_base makes the stored tokens
  # unreadable. That is survivable, because the fix is reconnecting Google,
  # which is one click. #read returns nil rather than raising on a bad envelope
  # so a rotation shows up as "not connected" instead of a 500 on every load.
  class SecretBox
    SALT = "ahoy_dashboard/google".freeze
    SERP_SALT = "ahoy_dashboard/serp".freeze
    ASSISTANT_SALT = "ahoy_dashboard/assistant".freeze
    CREDENTIAL_SALT = "ahoy_dashboard/credential".freeze
    AI_VISIBILITY_SALT = "ahoy_dashboard/ai_visibility".freeze
    LENGTH = 32

    class << self
      def write(value, salt: SALT)
        return nil if value.blank?

        encryptor(salt).encrypt_and_sign(value.to_s)
      end

      def read(value, salt: SALT)
        return nil if value.blank?

        encryptor(salt).decrypt_and_verify(value.to_s)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
        nil
      end

      def read_values(value:, salt:)
        stored = read(value, salt: salt)
        return {} if stored.blank?

        parsed = JSON.parse(stored)
        parsed.is_a?(Hash) ? parsed.symbolize_keys : {}
      rescue JSON::ParserError
        {}
      end

      def write_values(values:, salt:)
        cleaned = (values || {}).to_h.symbolize_keys
          .transform_values { |value| value.to_s.strip.presence }.compact

        write(cleaned.to_json, salt: salt) if cleaned.any?
      end

      private

      def encryptor(salt)
        encryptors[salt] ||= ActiveSupport::MessageEncryptor.new(key(salt))
      end

      def encryptors
        @encryptors ||= {}
      end

      def key(salt)
        ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base)
          .generate_key(salt, LENGTH)
      end
    end
  end
end
