module AhoyDashboard
  module Settings
    class AssistantProviderRowPresenter
      NOT_CHOSEN = "Saved without Use this one, so the settings saved here are not used.".freeze

      attr_reader :name, :record

      def self.all(records: AssistantProvider.ordered.index_by(&:name))
        AssistantProvider::NAMES.map { |name| new(name: name, record: records[name]) }
      end

      def initialize(name:, record: nil)
        @name = name.to_s
        @record = record
      end

      def reader
        Assistant::READERS.fetch(name)
      end

      def label
        reader[:label]
      end

      def local?
        reader[:local].present?
      end

      def in_use?
        Assistant.reader_name == name
      end

      def chosen_here?
        record&.active?
      end

      def badge
        return nil unless in_use?

        Assistant.available? ? { label: "Active", tone: :success } : { label: "Selected", tone: :neutral }
      end

      def note
        NOT_CHOSEN if in_use? && !chosen_here? && saved_anything?
      end

      def model
        chosen = in_use? ? Assistant.model_name : record&.model_name.presence || reader[:default_model]

        chosen.presence || "Not set"
      end

      def tuning
        return nil if record.nil?

        parts = []
        parts << "temperature #{record.temperature.to_f.to_s.delete_suffix(".0")}" unless record.temperature.nil?
        parts << "up to #{ActiveSupport::NumberHelper.number_to_delimited(record.max_tokens)} tokens" if record.max_tokens
        parts.join(", ").presence&.upcase_first
      end

      def key
        return "Not needed" if local?
        return used_key if in_use?

        record&.api_key.present? ? "Stored here" : "Missing"
      end

      def last_error
        record&.last_error.presence
      end

      def last_error_at
        record&.last_error_at
      end

      private

      def used_key
        Assistant.key_source == :stored ? "Stored here" : "Missing"
      end

      def saved_anything?
        record.present? && (record.api_key.present? || record.model.present? || record.api_base.present? ||
          !record.temperature.nil? || record.max_tokens.present?)
      end
    end
  end
end
