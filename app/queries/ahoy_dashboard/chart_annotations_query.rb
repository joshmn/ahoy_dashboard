# frozen_string_literal: true

module AhoyDashboard

  class ChartAnnotationsQuery < AhoyDashboard::Query
    def initialize(range:, bucket: :day)
      @range = range
      chosen = bucket.to_sym unless bucket.nil?
      @bucket = Annotation::BUCKETS.include?(chosen) ? chosen : :day
    end

    def call
      grouped.values.flatten
    end

    private

    attr_reader :range, :bucket

    def grouped
      return {} unless Installation.table?(Annotation.table_name)

      records
        .group_by { |note| Sql::Buckets.truncate(note.local_time, bucket) }
        .transform_values { |found| found.first(Annotation::PER_BUCKET) }
    end

    def records
      relation = Annotation.between(range.begin, range.end)
      return relation.order(:happened_at, :id).to_a unless Sql::Buckets::DATES.include?(bucket)

      expression = Sql::Buckets.sql("#{Annotation.table_name}.happened_at", bucket)
      ranked = relation.select("#{Annotation.table_name}.*",
        "ROW_NUMBER() OVER (PARTITION BY #{expression} ORDER BY happened_at, id) AS annotation_rank")
      Annotation.from("(#{ranked.to_sql}) #{Annotation.table_name}")
        .select(*Annotation.column_names).where("annotation_rank <= ?", Annotation::PER_BUCKET)
        .order(:happened_at, :id).to_a
    end
  end
end
