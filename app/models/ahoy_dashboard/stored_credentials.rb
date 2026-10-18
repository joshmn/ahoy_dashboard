module AhoyDashboard
  module StoredCredentials
    def credentials
      SecretBox.read_values(value: self[:credentials], salt: self.class::CREDENTIALS_SALT)
    end

    def credentials=(values)
      self[:credentials] = SecretBox.write_values(values: values, salt: self.class::CREDENTIALS_SALT)
    end

    def credential(key)
      credentials[key.to_sym]
    end
  end
end
