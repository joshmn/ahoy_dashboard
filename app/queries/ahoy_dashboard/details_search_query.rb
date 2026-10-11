module AhoyDashboard
  # The find-a-row box in the details modal.
  #
  # The narrowing is SQL rather than a select over the rows already fetched. The
  # modal shows a hundred rows out of however many the range holds, so a search
  # that only looked at those hundred would answer with whatever happened to be on
  # the page somebody was standing on.
  #
  # Every number beside a row is the number it had unsearched: a visit belongs to
  # one value of a visit dimension either way, and the session metrics on an event
  # dimension are still read over every visit containing the event. The term
  # decides which rows are listed and nothing else.
  class DetailsSearchQuery
    class << self
      def condition(dimension:, term:)
        term = clean(term)
        return if term.blank?

        ActiveRecord::Base.sanitize_sql_array(
          [ "#{dimension.sql} ilike :term", { term: "%#{ActiveRecord::Base.sanitize_sql_like(term)}%" } ]
        )
      end

      # The goals card's rows are the goals table rather than a group by, and
      # GoalsQuery already sorts and pages them in Ruby, so the name match happens
      # the same way. String#include? is also why a % or an _ is a character here.
      def goals(scope:, term:, limit:, offset:)
        term = clean(term)
        return AhoyDashboard::GoalsQuery.call(scope: scope, limit: limit, offset: offset) if term.blank?

        full = AhoyDashboard::GoalsQuery.call(scope: scope, limit: nil)
        matched = full.rows.select { |row| row.label.to_s.downcase.include?(term.downcase) }
        offset = [ offset.to_i, 0 ].max

        if limit.nil?
          return AhoyDashboard::BreakdownQuery::Result.new(rows: matched.drop(offset), total: full.total, more: false)
        end

        AhoyDashboard::BreakdownQuery::Result.new(
          rows: matched.slice(offset, limit) || [],
          total: full.total,
          more: matched.size > offset + limit
        )
      end

      private

      def clean(term)
        term.to_s.strip
      end
    end
  end
end
