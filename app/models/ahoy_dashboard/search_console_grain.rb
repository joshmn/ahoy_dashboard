module AhoyDashboard
  class SearchConsoleGrain < AhoyDashboard::Record
    self.abstract_class = true

    MEASURES = %i[clicks impressions ctr position].freeze

    KEY_BUDGET = 2_500

    KEY_COLUMNS = [].freeze

    scope :in_range, ->(range) { where(date: range.begin.to_date..range.end.to_date) }

    class << self
      def absorb(rows)
        return 0 if rows.blank?

        indexable = rows.reject { |row| over_budget?(row) }
        return 0 if indexable.empty?

        upsert_all(indexable, unique_by: self::UPSERT_KEYS, update_only: MEASURES)
        indexable.size
      end

      private

      def over_budget?(row)
        columns = self::KEY_COLUMNS
        bytes = columns.sum { |column| row[column].to_s.bytesize }
        return false if bytes <= KEY_BUDGET

        Rails.logger.warn(
          "#{model_name.element.tr("_", " ")} dropped for #{row[:date]}, #{columns.to_sentence} " \
          "#{columns.one? ? "is" : "are"} #{bytes} bytes and the index holds #{KEY_BUDGET}: " \
          "#{row[:query].to_s.truncate(60)}"
        )
        true
      end
    end
  end
end
