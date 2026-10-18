module AhoyDashboard
  class Form
    include ActiveModel::Model
    include ActiveModel::Attributes

    class TrimmedString < ActiveModel::Type::String
      private

      def cast_value(value)
        super.strip.presence
      end
    end

    TRIMMED = TrimmedString.new
    LABELS = {}.freeze

    class << self
      def human_attribute_name(attribute, options = {})
        self::LABELS.fetch(attribute.to_sym) { super }
      end

      private

      def normalize(params)
        hash = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params
        hash.to_h.symbolize_keys
      rescue StandardError
        {}
      end
    end

    def copy_errors_from(record)
      record.errors.messages.each do |attribute, messages|
        messages.each { |message| errors.add(attribute, message) }
      end

      self
    end
  end
end
