module AhoyDashboard
  class PropertyForm < AhoyDashboard::Form
    attribute :key, :string
    attribute :label, :string

    validates :key, presence: true
    validates :key, format: {
      with: AhoyDashboard::Property::NAME,
      message: "can be up to #{AhoyDashboard::Dimension::PROPERTY_NAME_LENGTH} characters, with no line breaks or tabs"
    }, allow_blank: true

    def key
      super().to_s.strip.presence
    end

    def label
      super().to_s.strip.presence
    end
  end
end
