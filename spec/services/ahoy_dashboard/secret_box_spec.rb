require "rails_helper"

RSpec.describe AhoyDashboard::SecretBox do
  it "treats an encrypted JSON value that is not an object as empty credentials" do
    salt = described_class::CREDENTIAL_SALT
    envelope = described_class.write('["invalid"]', salt: salt)

    expect(described_class.read_values(value: envelope, salt: salt)).to eq({})
  end

  it "round trips a value" do
    expect(described_class.read(described_class.write("hello"))).to eq("hello")
  end

  it "does not leave the value readable in the envelope" do
    expect(described_class.write("hello")).not_to include("hello")
  end

  it "writes nothing for a blank value" do
    expect(described_class.write(nil)).to be_nil
    expect(described_class.write("")).to be_nil
  end

  it "reads nothing from a blank value" do
    expect(described_class.read(nil)).to be_nil
    expect(described_class.read("")).to be_nil
  end

  it "hands back nil for an envelope it cannot open" do
    expect(described_class.read("not an envelope at all")).to be_nil
  end

  it "hands back nil for a tampered envelope" do
    envelope = described_class.write("hello")

    expect(described_class.read("#{envelope}x")).to be_nil
  end

  it "produces a different envelope each time for the same value" do
    expect(described_class.write("hello")).not_to eq(described_class.write("hello"))
  end

  describe "values written under another encryption setup" do
    let(:salt) { described_class::SERP_SALT }

    def key_for(digest)
      OpenSSL::PKCS5.pbkdf2_hmac(Rails.application.secret_key_base, salt, 2**16, 32, digest.new)
    end

    def sealed(value, digest:, cipher:, serializer:)
      ActiveSupport::MessageEncryptor.new(key_for(digest), cipher: cipher, serializer: serializer)
        .encrypt_and_sign(value)
    end

    def with_authenticated_encryption(value)
      before = ActiveSupport::MessageEncryptor.use_authenticated_message_encryption
      ActiveSupport::MessageEncryptor.use_authenticated_message_encryption = value
      yield
    ensure
      ActiveSupport::MessageEncryptor.use_authenticated_message_encryption = before
    end

    [ OpenSSL::Digest::SHA1, OpenSSL::Digest::SHA256 ].each do |digest|
      %w[aes-256-gcm aes-256-cbc].each do |cipher|
        [ Marshal, JSON ].each do |serializer|
          it "reads one sealed with #{cipher}, #{serializer} and a #{digest.name.demodulize} key" do
            envelope = sealed("stored-key", digest: digest, cipher: cipher, serializer: serializer)

            expect(described_class.read(envelope, salt: salt)).to eq("stored-key")
          end
        end
      end
    end

    it "reads one the host's own defaults wrote" do
      key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key(salt, 32)
      envelope = ActiveSupport::MessageEncryptor.new(key).encrypt_and_sign("stored-key")

      expect(described_class.read(envelope, salt: salt)).to eq("stored-key")
    end

    it "still reads an old cbc value after the host turns authenticated encryption on" do
      envelope = with_authenticated_encryption(false) do
        key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key(salt, 32)
        ActiveSupport::MessageEncryptor.new(key).encrypt_and_sign("stored-key")
      end

      with_authenticated_encryption(true) do
        expect(described_class.read(envelope, salt: salt)).to eq("stored-key")
      end
    end

    it "pins the cipher and serializer whatever the host's encryption defaults say" do
      envelope = with_authenticated_encryption(false) { described_class.write("stored-key", salt: salt) }
      key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key(salt, 32)
      pinned = ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm", serializer: Marshal)

      expect(pinned.decrypt_and_verify(envelope)).to eq("stored-key")
    end

    it "keys a value the way the host does, and still reads it once the host changes digest",
       if: ActiveSupport::KeyGenerator.respond_to?(:hash_digest_class=) do
      own_salt = "ahoy_dashboard/digest-#{SecureRandom.hex(4)}"
      before = ActiveSupport::KeyGenerator.hash_digest_class
      ActiveSupport::KeyGenerator.hash_digest_class = OpenSSL::Digest::SHA256
      envelope = described_class.write("stored-key", salt: own_salt)
      ActiveSupport::KeyGenerator.hash_digest_class = OpenSSL::Digest::SHA1
      key = OpenSSL::PKCS5.pbkdf2_hmac(Rails.application.secret_key_base, own_salt, 2**16, 32, OpenSSL::Digest::SHA256.new)

      expect(ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm", serializer: Marshal)
        .decrypt_and_verify(envelope)).to eq("stored-key")
      expect(described_class.read(envelope, salt: own_salt)).to eq("stored-key")
    ensure
      ActiveSupport::KeyGenerator.hash_digest_class = before
    end

    it "writes a value the host's own defaults still open, so going back a version keeps every secret" do
      envelope = described_class.write("stored-key", salt: salt)
      key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key(salt, 32)

      expect(ActiveSupport::MessageEncryptor.new(key).decrypt_and_verify(envelope)).to eq("stored-key")
    end

    it "keeps a value written for one purpose unreadable for another" do
      envelope = sealed("stored-key", digest: OpenSSL::Digest::SHA1, cipher: "aes-256-cbc", serializer: Marshal)

      expect(described_class.read(envelope, salt: described_class::ASSISTANT_SALT)).to be_nil
    end
  end
end
