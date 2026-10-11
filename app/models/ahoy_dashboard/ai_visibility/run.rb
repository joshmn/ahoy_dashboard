module AhoyDashboard
  module AiVisibility
    class Run < AhoyDashboard::Record
      has_many :answers, class_name: "AhoyDashboard::AiVisibility::Answer", inverse_of: :run,
                         dependent: :delete_all

      enum :status, { queued: "queued", skipped: "skipped" }, validate: true
      enum :trigger, { schedule: "schedule", manual: "manual" }, validate: true, prefix: :triggered_by

      scope :recent, -> { order(started_at: :desc) }

      def finished?
        skipped? || answers.completed.count >= requests
      end
    end
  end
end
