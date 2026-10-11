require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::Sql::InternalAddresses do
  let(:range) { dash_day_range(2026, 8, 10) }
  let(:at) { dash_time(2026, 8, 10, 9) }

  def visit_from(ip, visitor: ip.to_s.parameterize.presence || "blank")
    visit = dash_visit(started_at: at, visitor: visitor, ip: ip)
    dash_page_view(visit, path: "/", at: at)
    visit
  end

  def with_internal(list)
    AhoyDashboard::Preferences.write(:site, internal_ips: list)
    yield
  ensure
    AhoyDashboard::Preferences.clear(:site, :internal_ips)
  end

  def visitors(**options)
    AhoyDashboard::ScopeQuery.call(range: range, **options).visits.pluck(:visitor_token).sort
  end

  describe ".ranges" do
    it "ships loopback, private and unique local ranges" do
      expect(described_class.ranges.map(&:cidr)).to eq(
        %w[127.0.0.0/8 ::1/128 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 fc00::/7]
      )
    end

    it "drops an entry it cannot parse rather than raising" do
      with_internal([ "10.0.0.0/8", "not an address", "", nil, "300.1.1.1", "2001:db8::/32" ]) do
        expect(described_class.ranges.map(&:cidr)).to eq(%w[10.0.0.0/8 2001:db8::/32])
      end
    end

    it "normalises a bare address to a single host range" do
      with_internal([ "203.0.113.9", "::1" ]) do
        expect(described_class.ranges.map(&:cidr)).to eq(%w[203.0.113.9/32 ::1/128])
      end
    end

    it "is off when the list is empty" do
      with_internal([]) do
        expect(described_class).not_to be_enabled
        expect(described_class.condition).to be_nil
      end
    end
  end

  describe "the scope" do
    before do
      visit_from("203.0.113.10")
      visit_from("10.1.2.3")
      visit_from("192.168.0.7")
      visit_from("::1")
      visit_from("fd12::1")
      visit_from(nil)
      visit_from("garbage", visitor: "garbage")
      visit_from("999.1.1.1", visitor: "nines")
      visit_from("10.0.0.1, 203.0.113.5", visitor: "forwarded")
    end

    it "leaves internal addresses out by default" do
      expect(visitors).to eq(%w[203-0-113-10 blank forwarded garbage nines])
    end

    it "puts them back when asked" do
      expect(visitors(include_internal: true)).to eq(
        %w[1 10-1-2-3 192-168-0-7 203-0-113-10 blank fd12-1 forwarded garbage nines]
      )
    end

    it "counts everything when the list is empty" do
      with_internal([]) do
        expect(visitors).to eq(visitors(include_internal: true))
      end
    end

    it "never raises on a malformed stored address" do
      expect { visitors }.not_to raise_error
      expect(visitors).to include("garbage", "nines", "forwarded")
    end

    it "follows a configured list rather than the shipped one" do
      with_internal([ "203.0.113.0/24" ]) do
        expect(visitors).not_to include("203-0-113-10")
        expect(visitors).to include("10-1-2-3")
      end
    end

    it "keeps the events and the visits on the same set" do
      scope = AhoyDashboard::ScopeQuery.call(range: range)

      expect(scope.pageviews.count).to eq(5)
      expect(scope.total_visitors).to eq(5)
    end
  end

  describe "realtime" do
    it "leaves internal addresses out of who is on the site now" do
      travel_to(dash_time(2026, 8, 10, 9, 2)) do
        visit_from("203.0.113.10")
        visit_from("127.0.0.1")

        expect(AhoyDashboard::RealtimeQuery.call).to eq(1)
      end
    end
  end

  describe "network prefilter equivalence" do
    it "preserves classification across address families, compressed spellings, CIDR boundaries and malformed input" do
      connection = AhoyDashboard.visit.connection
      random = Random.new(417)
      addresses = [ nil, "", "garbage", "999.1.1.1", "010.0.0.1", "10.0.0.1/8",
        "10.0.0.1, 203.0.113.5", " ::1", "::1 ", "::ffff:192.168.0.1", "::FFFF:192.168.0.1",
        "0:0:0:0:0:ffff:192.168.0.1", "2001:db8::1%eth0", "fc00:::1", "::", "::1" ]
      addresses.concat((0..255).map { |octet| "#{octet}.16.0.1" })
      hextets = [ 0, 1, 0xf, 0x10, 0xff, 0x100, 0xfff, 0x1000, 0x2001, 0xfbff, 0xfc00, 0xfdff, 0xfe00, 0xffff ]
      hextets.concat(Array.new(64) { random.rand(0x10000) })
      hextets.each do |hextet|
        address = IPAddr.new((hextet << 112) | random.rand(1 << 112), Socket::AF_INET6)
        addresses.concat([ address.to_s, address.to_string, address.to_string.upcase ])
      end
      values = addresses.map { |address| "(#{connection.quote(address)}::text)" }.join(", ")
      networks = [ [ "0.0.0.0/0" ], [ "::/0" ], [ "::/128" ], [ "::1/128" ],
        [ "127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fc00::/7", "::1" ],
        [ "203.0.113.9/32" ], [ "192.168.0.0/31" ], [ "2001:db8::/32" ],
        [ "::ffff:0:0/96" ], [ "8000::/1" ], [ "100::/8" ], [ "f::/16" ] ]

      networks.each do |list|
        with_internal(list) do
          cidrs = described_class.ranges.map { |range| connection.quote(range.cidr) }.join(", ")
          original = <<~SQL.squish
            case when ahoy_visits.ip ~ #{connection.quote(described_class::IPV4)}
                      or ahoy_visits.ip ~* #{connection.quote(described_class::IPV6)}
                 then ahoy_visits.ip::inet <<= any(array[#{cidrs}]::inet[]) else false end
          SQL
          mismatches = connection.select_values(<<~SQL)
            select ip from (values #{values}) as ahoy_visits(ip)
            where (#{original}) is distinct from (#{described_class.condition})
          SQL

          expect(mismatches).to be_empty, "classification changed for #{list.inspect}: #{mismatches.inspect}"
        end
      end
    end
  end
end
