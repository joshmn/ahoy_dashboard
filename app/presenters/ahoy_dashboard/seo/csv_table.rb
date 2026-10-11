module AhoyDashboard
  module Seo
    class CsvTable
      attr_reader :key, :label, :headers

      def initialize(key:, label:, headers:, &body)
        @key = key.to_s
        @label = label
        @headers = headers
        @body = body
      end

      def rows
        Enumerator.new do |out|
          out << headers
          @body.call.each { |row| out << row }
        end
      end
    end
  end
end
