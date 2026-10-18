module AhoyDashboard
  module SeverityBadge
    TONES = { "high" => :danger, "medium" => :warning }.freeze

    def self.tone(severity)
      TONES.fetch(severity.to_s, :neutral)
    end

    def severity_label
      severity.to_s.capitalize
    end

    def severity_tone
      SeverityBadge.tone(severity)
    end
  end
end
