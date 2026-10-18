module AhoyDashboard
  class GoogleAccount < AhoyDashboard::Record
    include LastError

    REFRESH_MARGIN = 1.minute

    DOMAIN_PREFIX = "sc-domain:".freeze

    def self.current
      order(:id).first
    end

    def access_token
      SecretBox.read(self[:access_token])
    end

    def access_token=(value)
      self[:access_token] = SecretBox.write(value)
    end

    def refresh_token
      SecretBox.read(self[:refresh_token])
    end

    def refresh_token=(value)
      return if value.blank?

      self[:refresh_token] = SecretBox.write(value)
    end

    def connected?
      refresh_token.present?
    end

    def property_selected?
      property_uri.present?
    end

    def ready?
      connected? && property_selected?
    end

    def expired?(now: Time.current)
      expires_at.blank? || expires_at <= now + REFRESH_MARGIN
    end

    def property_label
      return nil if property_uri.blank?
      return property_uri.delete_prefix(DOMAIN_PREFIX) if domain_property?

      property_uri
    end

    def domain_property?
      property_uri.to_s.start_with?(DOMAIN_PREFIX)
    end
  end
end
