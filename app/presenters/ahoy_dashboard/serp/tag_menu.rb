module AhoyDashboard
  module Serp
    class TagMenu
      ALL_LABEL = "All tags".freeze

      attr_reader :tags, :current

      def initialize(tags:, current:, url:)
        @tags = tags
        @current = current.presence
        @url = url
      end

      def show?
        tags.any? || current.present?
      end

      def label
        current ? "Tag: #{current}" : ALL_LABEL
      end

      def items
        [
          { label: ALL_LABEL, url: url.call(nil), active: current.nil? },
          *tags.map { |tag| { label: tag, url: url.call(tag), active: tag == current } }
        ]
      end

      def clear_action(data: {})
        { label: "Show all tags", url: url.call(nil), data: data, primary: false }
      end

      private

      attr_reader :url
    end
  end
end
