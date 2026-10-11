module AhoyDashboard
  # A named bag of secrets that does not carry enough shape to earn its own
  # table. One row per purpose (a name, unique), one encrypted JSON blob of
  # key/value pairs. The Google OAuth client id and secret live here, under
  # the name "google_oauth_client", kept apart from GoogleAccount on purpose:
  # that table is the token grant, dropped whole on disconnect, and the OAuth
  # client from the Google Cloud console must survive a disconnect.
  class Credential < AhoyDashboard::Record
    validates :name, presence: true, uniqueness: true

    def self.for(name)
      find_by(name: name.to_s)
    end

    def self.fetch(name)
      self.for(name) || new(name: name.to_s)
    end

    def values
      SecretBox.read_values(value: self[:secrets], salt: SecretBox::CREDENTIAL_SALT)
    end

    def values=(values)
      self[:secrets] = SecretBox.write_values(values: values, salt: SecretBox::CREDENTIAL_SALT)
    end

    def value(key)
      values[key.to_sym]
    end

    def configured?(*keys)
      keys.all? { |key| value(key).present? }
    end
  end
end
