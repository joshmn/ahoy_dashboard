module AhoyDashboard
  module LastError
    LENGTH = 255

    def record_error!(message)
      update_columns(last_error: message.to_s.first(LENGTH), last_error_at: Time.current)
    end

    def clear_error!
      return if last_error.blank?

      update_columns(last_error: nil, last_error_at: nil)
    end
  end
end
