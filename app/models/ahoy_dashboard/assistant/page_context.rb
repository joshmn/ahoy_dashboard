module AhoyDashboard
  module Assistant
    # What was on screen when somebody opened the ask panel. "This page" is the
    # whole reason the panel exists, and it is the one thing a conversation
    # started from the Ask screen cannot work out for itself: the model can read
    # every table in the database and still has no idea which of them the person
    # is looking at.
    #
    # Snapshotted onto the chat rather than re-derived on every turn. The
    # question was asked about a particular slice, and a follow-up an hour later
    # is still about that slice even if the dashboard has moved on.
    class PageContext
      def self.call(**options)
        new(**options).to_h
      end

      # One line out of a stored context, in the words the panel prints and the
      # model reads, so what the subline says the question is about and what the
      # model is told it is about cannot drift apart.
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

      # Longest path first, so /ahoy_dashboard/settings/serp_keywords is not read as
      # the dashboard, which every path under the mount starts with. The dashboard
      # itself only ever matches exactly, for the same reason: a screen this has
      # never heard of is not the dashboard, and printing the path back is more
      # honest than naming the wrong page.
      def screen
        @screen ||= Tools::AppContext::SCREENS
          .sort_by { |_name, entry| -entry[:path].length }
          .find { |_name, entry| under?(entry[:path]) }
      end

      # Screen paths are stored relative to the mount, so the request path is
      # cut back to the same shape before either is compared. The dashboard
      # itself is the empty string and only ever matches exactly.
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

      # The menu item's own words for a named range and the dates for a hand
      # picked one, the same way every header on the dashboard says it. The
      # model is told the window as words and works the dates out itself, which
      # is what the rest of the prompt already asks of it.
      def window
        return nil if query.nil?

        query.period.custom? ? query.range_label : query.period.label
      end

      def filter_labels
        return [] if query.nil? || query.filters.empty?

        FilterWording.labels(query.filters)
      end
    end
  end
end
