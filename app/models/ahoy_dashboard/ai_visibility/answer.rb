module AhoyDashboard
  module AiVisibility
    class Answer < AhoyDashboard::Record
      belongs_to :run, class_name: "AhoyDashboard::AiVisibility::Run", inverse_of: :answers
      belongs_to :prompt, class_name: "AhoyDashboard::AiVisibility::Prompt", inverse_of: :answers
      has_many :sources, -> { order(:slot) }, class_name: "AhoyDashboard::AiVisibility::Source",
                                              inverse_of: :answer, dependent: :delete_all

      enum :status, { pending: "pending", processing: "processing", success: "success", failed: "failed" }, validate: true

      validates :assistant, inclusion: { in: AiVisibility::NAMES }
      validates :model, presence: true

      scope :in_range, ->(range) { where(asked_at: range) }
      scope :completed, -> { where(status: %w[success failed]) }
      scope :for_assistant, ->(name) { name.present? ? where(assistant: name.to_s) : all }
      scope :for_model, ->(model) { model.present? ? where(model: model.to_s) : all }
    end
  end
end
