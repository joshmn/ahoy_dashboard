require "net/http"
require "tempfile"

module AhoyDashboard
  module Places
    # The published list, read a batch at a time.
    #
    # It is sixteen megabytes and a quarter of a million lines, so it lands in a
    # tempfile and is parsed off disk rather than held in memory as one string.
    #
    # The file is named for the month it was published in and the old ones stay
    # up, so a run on the second of the month asks for this month and walks
    # backwards if it is not there yet. That is what makes a missed run harmless:
    # whenever it next runs it gets the newest list that exists.
    class Source
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 120
      MAX_REDIRECTS = 3
      LOOKBACK = 3

      HEADERS = %w[location_code location_name location_code_parent country_iso_code location_type].freeze

      Row = Data.define(:code, :parent_code, :name, :label, :country_code, :kind, :depth)

      attr_reader :month

      def initialize(on: nil, postal_codes: nil, lookback: LOOKBACK)
        @on = on || AhoyDashboard.time_zone.today
        @postal_codes = postal_codes.nil? ? Places.postal_codes? : postal_codes
        @lookback = lookback
        @month = nil
      end

      def url
        Places.source_url(@month || @on.beginning_of_month)
      end

      def each_slice(size)
        path = download

        rows = []
        checked = false
        CSV.foreach(path, headers: true) do |line|
          checked ||= check_columns(line)
          row = build(line)
          next if row.nil?

          rows << row
          next if rows.size < size

          yield rows
          rows = []
        end

        yield rows if rows.any?
      ensure
        File.unlink(path) if path && File.exist?(path)
      end

      private

      # A silent zero row sync is worse than a failed one: the picker would go on
      # answering with a list that is however old it already was, and nothing
      # would say so. If the columns move, this stops.
      def check_columns(line)
        missing = HEADERS - line.headers.map(&:to_s)
        return true if missing.empty?

        raise Error, "the place list at #{url} is missing #{missing.join(', ')}"
      end

      def download
        errors = []

        (0..@lookback).each do |back|
          @month = @on.beginning_of_month - back.months
          path = fetch(Places.source_url(@month))
          return path if path

          errors << @month.strftime("%Y-%m")
        end

        raise Error, "no place list published for #{errors.join(', ')}"
      end

      def fetch(address, redirects: 0)
        uri = URI.parse(address)
        file = Tempfile.new([ "ahoy_dashboard_places", ".csv" ])
        file.binmode

        response = stream(uri, file)

        if response.is_a?(Net::HTTPRedirection) && redirects < MAX_REDIRECTS
          file.close!
          return fetch(URI.join(address, response["location"]).to_s, redirects: redirects + 1)
        end

        file.close
        return file.path if response.is_a?(Net::HTTPSuccess) && File.size(file.path).positive?

        file.unlink
        return nil if response.is_a?(Net::HTTPNotFound)

        raise Error, "the place list at #{address} answered #{response.code}"
      rescue Error
        raise
      rescue StandardError => e
        file&.close
        file&.unlink if file&.path && File.exist?(file.path)
        raise Error, "could not read the place list at #{address}: #{e.class}: #{e.message}"
      end

      def stream(uri, file)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                            open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          request = Net::HTTP::Get.new(uri)
          request["User-Agent"] = AhoyDashboard.user_agent

          http.request(request) do |response|
            response.read_body { |chunk| file.write(chunk) } if response.is_a?(Net::HTTPSuccess)
            return response
          end
        end
      end

      def build(line)
        code = line["location_code"].to_i
        name = line["location_name"].to_s.strip
        country = line["country_iso_code"].to_s.strip.downcase
        kind = line["location_type"].to_s.strip.downcase

        return nil if code.zero? || name.empty? || country.length != 2
        return nil if kind == Places::POSTAL && !@postal_codes

        parts = name.split(Place::SEPARATOR)

        Row.new(
          code: code,
          parent_code: line["location_code_parent"].presence&.to_i,
          name: name,
          label: parts.first.to_s.strip,
          country_code: country,
          kind: kind,
          depth: parts.size - 1
        )
      end
    end
  end
end
