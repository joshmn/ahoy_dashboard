module AhoyDashboard
  module Assistant
    class PageContext
      def self.call(**options)
        new(**options).to_h
      end

      def self.line(context)
        return nil unless context.is_a?(Hash) && context["path"].present?

        parts = [ context["screen"].presence || context["path"].split("?").first, context["window"].presence ].compact
        filters = Array(context["filters"]).reject(&:blank?)
        parts << "filtered to #{filters.to_sentence}" if filters.any?

        parts.join(", ")
      end

      def initialize(path:, query: nil)
        @path = path.to_s.presence || AhoyDashboard.mount_path
        @query = query
      end

      def to_h
        {
          "path" => path,
          "screen" => screen&.first,
          "does" => screen&.last&.fetch(:does, nil),
          "window" => window,
          "filters" => filter_labels,
          "crawlers" => (query&.include_crawlers? ? "shown" : "excluded"),
          Slice::KEY => (Slice.snapshot(query) if query)
        }.merge(query ? FilterWording.hidden_traffic(query).transform_keys(&:to_s) : {})
          .reject { |_key, value| value.blank? }
      end

      private

      attr_reader :path, :query

      def screen
        @screen ||= Tools::AppContext::SCREENS
          .sort_by { |_name, entry| -entry[:path].length }
          .find { |_name, entry| under?(entry[:path]) }
      end

      def under?(candidate)
        return relative_path.in?([ "", "dashboard" ]) if candidate.empty?

        relative_path == candidate || relative_path.start_with?("#{candidate}/")
      end

      def bare_path
        @bare_path ||= path.split("?").first.to_s.chomp("/").presence || AhoyDashboard.mount_path
      end

      def relative_path
        @relative_path ||= bare_path
          .delete_prefix(AhoyDashboard.mount_path.to_s.chomp("/"))
          .delete_prefix("/")
      end

      def window
        return nil if query.nil?

        query.range_title
      end

      def filter_labels
        return [] if query.nil? || query.filters.empty?

        FilterWording.labels(query.filters)
      end
    end
  end
end
