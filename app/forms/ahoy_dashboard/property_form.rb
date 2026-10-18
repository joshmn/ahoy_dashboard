module AhoyDashboard
  class PropertyForm < AhoyDashboard::Form
    attribute :key, TRIMMED
    attribute :label, TRIMMED

    validates :key, presence: true
    validates :key, format: {
      with: AhoyDashboard::Property::NAME,
      message: "can be up to #{AhoyDashboard::Dimension::PROPERTY_NAME_LENGTH} characters, with no line breaks or tabs"
    }, allow_blank: true

    def record_attributes
      { key: key, label: label }
    end

    def add_duplicate_error
      errors.add(:key, "is already on the list")
    end
  end
end
