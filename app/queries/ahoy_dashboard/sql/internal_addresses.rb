require "ipaddr"

module AhoyDashboard
  module Sql
    class InternalAddresses
      COLUMN = "ahoy_visits.ip".freeze
      OCTET = "(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])".freeze
      IPV4_BODY = "#{OCTET}([.]#{OCTET}){3}".freeze
      IPV4 = "^#{IPV4_BODY}$".freeze
      HEXTET = "[0-9a-f]{1,4}".freeze
      IPV6 = [
        "^(",
        [
          "(#{HEXTET}:){7}#{HEXTET}",
          "(#{HEXTET}:){1,7}:",
          "(#{HEXTET}:){1,6}:#{HEXTET}",
          "(#{HEXTET}:){1,5}(:#{HEXTET}){1,2}",
          "(#{HEXTET}:){1,4}(:#{HEXTET}){1,3}",
          "(#{HEXTET}:){1,3}(:#{HEXTET}){1,4}",
          "(#{HEXTET}:){1,2}(:#{HEXTET}){1,5}",
          "#{HEXTET}:(:#{HEXTET}){1,6}",
          ":(:#{HEXTET}){1,7}",
          "::",
          "::ffff:#{IPV4_BODY}"
        ].join("|"),
        ")$"
      ].join.freeze

      Range = Data.define(:cidr, :label)

      class << self
        def ranges
          Preferences.read(:site, :internal_ips).map { |entry| parse(entry) }.select { |value| value }
        end

        def enabled?
          ranges.any?
        end

        def condition
          listed = ranges
          return nil if listed.empty?

          connection = AhoyDashboard.visit.connection
          addresses = listed.map { |range| IPAddr.new(range.cidr) }
          ipv4, ipv6 = addresses.partition(&:ipv4?)

          <<~SQL.squish
            (case when position(':' in #{COLUMN}) > 0
                  then #{family_condition(connection, ipv6, ipv6: true)}
                  else #{family_condition(connection, ipv4, ipv6: false)} end)
          SQL
        end

        def exclude(relation)
          sql = condition

          sql.nil? ? relation : relation.where(Arel.sql("not #{sql}"))
        end

        def only(relation)
          sql = condition

          sql.nil? ? relation.none : relation.where(Arel.sql(sql))
        end

        private

        # Reject impossible networks before validating the whole address. These
        # prefixes are only a necessary condition: the original validation and
        # inet comparison still decide membership, including malformed input.
        def family_condition(connection, addresses, ipv6:)
          return "false" if addresses.empty?

          cidrs = addresses.map { |address| connection.quote("#{address}/#{address.prefix}") }.join(", ")
          pattern = connection.quote(ipv6 ? IPV6 : IPV4)
          validation = "#{COLUMN} #{ipv6 ? '~*' : '~'} #{pattern}"
          membership = "case when #{validation} then #{COLUMN}::inet <<= any(array[#{cidrs}]::inet[]) else false end"
          candidate = if ipv6
            characters = ipv6_initials(addresses)
            "left(#{COLUMN}, 1) in (#{characters.map { |char| connection.quote(char) }.join(', ')})"
          else
            octets = addresses.flat_map do |address|
              first = address.to_range.begin.to_i >> 24
              last = address.to_range.end.to_i >> 24
              (first..last).map(&:to_s)
            end.uniq
            "split_part(#{COLUMN}, '.', 1) in (#{octets.map { |octet| connection.quote(octet) }.join(', ')})"
          end

          "case when #{candidate} then (#{membership}) else false end"
        end

        # The first hextet can omit leading zeroes or be compressed altogether.
        # Include every spelling that could overlap a configured network; false
        # positives are harmless because family_condition validates and compares.
        def ipv6_initials(addresses)
          addresses.flat_map do |address|
            first = address.to_range.begin.to_i >> 112
            last = address.to_range.end.to_i >> 112
            characters = []
            characters << ":" if first.zero?
            characters << "0" if first <= 0xfff
            (1..15).each do |digit|
              possible = (0..3).any? do |power|
                low = digit * (16**power)
                high = (digit + 1) * (16**power) - 1
                low <= last && high >= first
              end
              next unless possible

              characters.concat([ digit.to_s(16), digit.to_s(16).upcase ])
            end
            characters
          end.uniq
        end

        def parse(entry)
          text = entry.to_s.strip
          return nil if text.empty?

          address = IPAddr.new(text)

          Range.new(cidr: "#{address}/#{address.prefix}", label: text)
        rescue IPAddr::Error
          nil
        end
      end
    end
  end
end
