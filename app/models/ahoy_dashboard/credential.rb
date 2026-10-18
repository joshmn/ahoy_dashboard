module AhoyDashboard
  class Credential < AhoyDashboard::Record
    validates :name, presence: true, uniqueness: true

    def self.for(name)
      find_by(name: name.to_s)
    end

    def self.fetch(name)
      self.for(name) || new(name: name.to_s)
    end

    def credentials
      SecretBox.read_values(value: self[:secrets], salt: SecretBox::CREDENTIAL_SALT)
    end

    def credentials=(values)
      self[:secrets] = SecretBox.write_values(values: values, salt: SecretBox::CREDENTIAL_SALT)
    end

    def credential(key)
      credentials[key.to_sym]
    end
  end
end
