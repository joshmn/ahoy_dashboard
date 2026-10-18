module AhoyDashboard
  class SegmentDecorator < AhoyDashboard::Decorator
    DEFAULT_LABEL = "The default".freeze

    def meta
      return [ AhoyDashboard::Segment::KIND_LABEL, unreadable_note ].join(". ") unless readable?

      [ (DEFAULT_LABEL if applied_by_default?), AhoyDashboard::Segment::KIND_LABEL, dates ].compact.join(". ")
    end

    def unreadable_note
      "Not being applied. It names something the dashboard cannot read any more."
    end

    def summary
      return unreadable_note unless readable?

      to_filters.sentence
    end

    def count_label
      "#{entries.size} #{"filter".pluralize(entries.size)}"
    end
  end
end
