module AhoyDashboard
  module Settings
    class PagePatternPreview
      SHOWN = 8
      POOL = 100
      MODAL_KEY = "page-group-matches".freeze

      attr_reader :paths, :patterns

      def initialize(paths:, patterns:)
        @paths = paths
        @patterns = patterns
      end

      def matches
        @matches ||= patterns.empty? ? [] : paths.select { |path, _| patterns.any? { |pattern| match?(path, pattern) } }
      end

      def shown
        matches.first(SHOWN)
      end

      def more
        [ matches.size - SHOWN, 0 ].max
      end

      def modal_title
        "All #{matches.size} #{"page".pluralize(matches.size)} it groups"
      end

      def summary
        return "No page views in the last 30 days to check against." if paths.empty?
        return "Type a pattern to see which pages it groups." if patterns.empty?

        "Matches #{matches.empty? ? "none" : matches.size} of #{pool}."
      end

      private

      def pool
        return "the #{POOL} most visited pages in the last 30 days" if paths.size >= POOL

        "#{paths.size} #{"page".pluralize(paths.size)} visited in the last 30 days"
      end

      def match?(path, pattern)
        return path.to_s == pattern unless pattern.end_with?(PageGroup::WILDCARD)

        prefix = pattern.delete_suffix(PageGroup::WILDCARD)
        prefix.present? && path.to_s.start_with?(prefix)
      end
    end
  end
end
