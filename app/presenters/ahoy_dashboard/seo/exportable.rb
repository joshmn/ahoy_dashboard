module AhoyDashboard
  module Seo
    module Exportable
      def csv_tables
        []
      end

      def csv_table(key = nil)
        tables = csv_tables
        return nil if tables.empty?
        return tables.first if key.blank?

        tables.find { |table| table.key == key.to_s }
      end

      def csv_path(key = nil)
        params = export_params.merge(format: :csv)
        params = params.merge(table: key.to_s) if key.present? && csv_tables.many?

        export_path(params)
      end

      def csv_filename(table)
        parts = [ "ahoy-dashboard-seo", export_key ]
        parts << table.key.tr("_", "-") if csv_tables.many?
        parts << Time.current.in_time_zone(AhoyDashboard.time_zone).to_date.iso8601

        "#{parts.join("-")}.csv"
      end

      def csv_percent(value, places: 1)
        value.nil? ? nil : (value.to_f * 100).round(places)
      end

      def csv_date(value)
        AhoyDashboard::DateFormat.local(value)&.iso8601
      end

      def csv_time(value)
        value&.in_time_zone(AhoyDashboard.time_zone)&.iso8601
      end
    end
  end
end
