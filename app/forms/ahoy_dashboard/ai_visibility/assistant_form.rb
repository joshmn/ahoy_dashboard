module AhoyDashboard
  module AiVisibility
    class AssistantForm < AhoyDashboard::Form
      include SecretFields

      attribute :name, :string
      attribute :enabled, :boolean, default: true
      attribute :models, default: -> { [] }
      attribute :other_models, :string

      validates :name, inclusion: { in: AiVisibility::NAMES, message: "is not an assistant this asks" }
      validate :a_model_when_asked

      def self.from_record(assistant)
        chosen = assistant.models.presence || [ AiVisibility.default_model(assistant.name) ]
        catalog = AiVisibility.catalog(assistant.name)

        new(name: assistant.name, enabled: assistant.new_record? || assistant.enabled?,
            models: chosen & catalog, other_models: (chosen - catalog).join(", "))
      end

      def label
        AiVisibility.label(name)
      end

      def default_model
        AiVisibility.default_model(name)
      end

      def provider
        AiVisibility::ASSISTANTS.fetch(name.to_s)[:provider]
      end

      def model_choices
        AiVisibility.catalog(name).map { |model| [ model, model == default_model ? "#{model} (default)" : model ] }
      end

      def model_list
        typed = other_models.to_s.split(/[\s,]+/)

        (Array(models) + typed).map { |model| model.to_s.strip }.reject(&:blank?).uniq
      end

      private

      def a_model_when_asked
        return unless enabled && model_list.empty?

        errors.add(:models, "need at least one, or turn #{label} off")
      end
    end
  end
end
