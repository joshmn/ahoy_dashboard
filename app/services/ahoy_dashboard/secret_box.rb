module AhoyDashboard
  class SecretBox
    SALT = "ahoy_dashboard/google".freeze
    SERP_SALT = "ahoy_dashboard/serp".freeze
    ASSISTANT_SALT = "ahoy_dashboard/assistant".freeze
    CREDENTIAL_SALT = "ahoy_dashboard/credential".freeze
    AI_VISIBILITY_SALT = "ahoy_dashboard/ai_visibility".freeze
    LENGTH = 32
    ITERATIONS = 2**16

    module JsonSerializer
      module_function

      def dump(value)
        JSON.generate(value)
      end

      def load(value)
        JSON.parse(value)
      end
    end

    Shape = Data.define(:digest, :cipher, :serializer)

    DIGESTS = [ OpenSSL::Digest::SHA1, OpenSSL::Digest::SHA256 ].freeze
    CIPHERS = %w[aes-256-gcm aes-256-cbc].freeze
    SERIALIZERS = [ JsonSerializer, Marshal ].freeze
    HOST_DEFAULT = Shape.new(digest: nil, cipher: nil, serializer: nil)
    WRITTEN = Shape.new(digest: nil, cipher: "aes-256-gcm", serializer: Marshal)
    READ = (DIGESTS.product(CIPHERS, SERIALIZERS).map { |digest, cipher, serializer|
      Shape.new(digest: digest, cipher: cipher, serializer: serializer)
    } + [ WRITTEN, HOST_DEFAULT ]).freeze
    UNREADABLE = [ ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature,
                   JSON::ParserError ].freeze

    class << self
      def write(value, salt: SALT)
        return nil if value.blank?

        encryptor(salt, WRITTEN).encrypt_and_sign(value.to_s)
      end

      def read(value, salt: SALT)
        return nil if value.blank?

        READ.each do |shape|
          opened = attempt(encryptor(salt, shape), value.to_s)
          return opened unless opened.nil?
        end

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

      def attempt(encryptor, value)
        encryptor.decrypt_and_verify(value)
      rescue *UNREADABLE
        nil
      end

      def encryptor(salt, shape)
        encryptors[[ salt, shape ]] ||= build(salt, shape)
      end

      def build(salt, shape)
        secret = shape.digest ? key(salt, shape.digest) : host_key(salt)
        return ActiveSupport::MessageEncryptor.new(secret) if shape.cipher.nil?

        ActiveSupport::MessageEncryptor.new(secret, cipher: shape.cipher, serializer: shape.serializer)
      end

      def encryptors
        @encryptors ||= {}
      end

      def keys
        @keys ||= {}
      end

      def key(salt, digest)
        keys[[ salt, digest ]] ||= OpenSSL::PKCS5.pbkdf2_hmac(Rails.application.secret_key_base, salt, ITERATIONS,
                                                             LENGTH, digest.new)
      end

      def host_key(salt)
        ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base)
          .generate_key(salt, LENGTH)
      end
    end
  end
end
