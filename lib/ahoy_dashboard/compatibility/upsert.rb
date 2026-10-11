# frozen_string_literal: true

module AhoyDashboard

  module Compatibility

    class Upsert
      def initialize(model:, rows:, unique_by:, update_only: nil, record_timestamps: nil, on_duplicate: nil,
                     returning: nil)
        @model = model
        @rows = rows.map(&:stringify_keys)
        @unique_by = Array(unique_by).map(&:to_s)
        @update_only = update_only && update_only.map(&:to_s)
        @timestamps = record_timestamps.nil? ? model.record_timestamps : record_timestamps
        @on_duplicate = on_duplicate
        @returning = returning
        @generated_updated_at = @timestamps && @rows.all? { |row| !row.key?("updated_at") }
      end

      def call
        return ActiveRecord::Result.new([], []) if rows.empty?

        timestamp_rows
        keys = rows.first.keys
        raise ArgumentError, "all rows must have the same keys" unless rows.all? { |row| row.keys.sort == keys.sort }
        unknown = (keys + Array(update_only) + unique_by) - model.column_names
        raise ActiveModel::UnknownAttributeError.new(model.new, unknown.first) if unknown.any?

        values = rows.map { |row| "(#{keys.map { |key| quote_value(key: key, value: row.fetch(key)) }.join(', ')})" }
        columns = keys.map { |key| connection.quote_column_name(key) }.join(", ")
        sql = "INSERT INTO #{model.quoted_table_name} (#{columns}) VALUES #{values.join(', ')} " \
              "ON CONFLICT (#{unique_by.map { |key| connection.quote_column_name(key) }.join(', ')}) " \
              "#{updates(keys)}#{returning_sql}"
        connection.exec_query(sql, "#{model.name} Bulk Upsert")
      end

      private

      attr_reader :model, :rows, :unique_by, :update_only, :timestamps, :on_duplicate, :returning,
                  :generated_updated_at

      def connection
        model.connection
      end

      def timestamp_rows
        return unless timestamps

        now = Time.current
        columns = %w[created_at updated_at] & model.column_names
        rows.each { |row| columns.each { |column| row[column] = now unless row.key?(column) } }
      end

      def quote_value(key:, value:)
        connection.quote(model.type_for_attribute(key).serialize(value))
      end

      def updates(keys)
        return "DO UPDATE SET #{on_duplicate}" if on_duplicate

        writable = update_only || keys - unique_by - Array(model.primary_key) - model.readonly_attributes.to_a - ["created_at"]
        writable -= ["updated_at"] if generated_updated_at && !update_only
        return "DO NOTHING" if writable.empty?

        assignments = writable.map do |key|
          column = connection.quote_column_name(key)
          "#{column} = excluded.#{column}"
        end
        if timestamps && keys.include?("updated_at") && !writable.include?("updated_at")
          unchanged = writable.map do |key|
            column = connection.quote_column_name(key)
            "#{model.quoted_table_name}.#{column} IS NOT DISTINCT FROM excluded.#{column}"
          end.join(" AND ")
          assignments << "updated_at = CASE WHEN #{unchanged} THEN #{model.quoted_table_name}.updated_at ELSE excluded.updated_at END"
        end
        "DO UPDATE SET #{assignments.join(', ')}"
      end

      def returning_sql
        return "" if returning == false

        columns = returning || Array(model.primary_key)
        " RETURNING #{Array(columns).map { |column| connection.quote_column_name(column) }.join(', ')}"
      end
    end
  end
end
