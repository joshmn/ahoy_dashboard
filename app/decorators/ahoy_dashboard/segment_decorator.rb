module AhoyDashboard
  # How a segment says itself, on the filter dialog and on the settings screen. Both
  # read the same methods so the two cannot describe one segment differently.
  class SegmentDecorator < AhoyDashboard::Decorator
    DATE = "%-d %b".freeze

    DEFAULT_LABEL = "The default".freeze

    def meta
      return [ AhoyDashboard::Segment::KIND_LABEL, unreadable_note ].join(". ") unless readable?

      [ (DEFAULT_LABEL if applied_by_default?), AhoyDashboard::Segment::KIND_LABEL, dates ].compact.join(". ")
    end

    def dates
      return "Created #{on(created_at)}" if created_at.to_i == updated_at.to_i

      "Created #{on(created_at)}, last updated #{on(updated_at)}"
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

    private

    # Every date the operator is shown is in the dashboard's own zone, like every
    # other date in this subsystem, rather than in UTC.
    def on(time)
      time.in_time_zone(AhoyDashboard.time_zone).strftime(DATE)
    end
  end
end
