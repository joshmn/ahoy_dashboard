module AhoyDashboard
  # The one connected Google account, and which Search Console property it
  # reads. One admin, so one row: .current is the whole lookup and .connect!
  # replaces rather than adds.
  #
  # Both tokens are stored through AhoyDashboard::SecretBox. The reader hands back
  # nil for an envelope it cannot open, so a rotated secret_key_base reads as
  # disconnected rather than raising.
  class GoogleAccount < AhoyDashboard::Record
    # Google's access tokens last an hour. Refreshed a minute early so a long
    # request cannot start valid and finish expired.
    REFRESH_MARGIN = 1.minute

    DOMAIN_PREFIX = "sc-domain:".freeze

    def self.current
      order(:id).first
    end

    def self.connected?
      current&.connected? || false
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
      # Google returns a refresh token on the first authorization only, so a
      # reconnect that comes back without one must not wipe the one that works.
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

    # The label Search Console itself uses. A domain property covers every
    # subdomain and both schemes, which is why it is worth showing as different.
    def property_label
      return nil if property_uri.blank?
      return property_uri.delete_prefix(DOMAIN_PREFIX) if domain_property?

      property_uri
    end

    def domain_property?
      property_uri.to_s.start_with?(DOMAIN_PREFIX)
    end

    def record_error!(message)
      update_columns(last_error: message.to_s.first(255), last_error_at: Time.current)
    end

    def clear_error!
      return if last_error.blank?

      update_columns(last_error: nil, last_error_at: nil)
    end
  end
end
