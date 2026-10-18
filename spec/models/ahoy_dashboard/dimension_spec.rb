require "rails_helper"

RSpec.describe AhoyDashboard::Dimension do
  describe "the registry" do
    it "finds every registered dimension by its own key" do
      described_class::ALL.each do |dimension|
        expect(described_class.find(dimension.key)).to eq(dimension)
        expect(dimension.to_param).to eq(dimension.key)
      end
    end

    it "files every dimension under a filter dialog heading" do
      expect(described_class::ALL.map(&:group).uniq).to all(
        be_in([ "Page", "Source", "Location", "Device", "Behaviour" ])
      )
    end

    it "scopes every dimension to either a visit or an event" do
      expect(described_class::ALL.map { |dimension| dimension.scope.to_sym }.uniq - [ :visit, :event ]).to be_empty
    end

    it "gives every dimension a label, a filter label and an unknown label" do
      described_class::ALL.each do |dimension|
        expect(dimension.label).to be_present, "#{dimension.key} has no label"
        expect(dimension.filter_label).to be_present, "#{dimension.key} has no filter label"
        expect(dimension.unknown_label).to be_present, "#{dimension.key} has no unknown label"
      end
    end

    it "defaults an unknown value to (not set)" do
      expect(described_class.find("country").unknown_label).to eq("(not set)")
    end

    it "carries the dimensions the cards are built on" do
      expect(described_class.find("page").scope.to_sym).to eq(:event)
      expect(described_class.find("page").sql.to_s).to include("ahoy_events.properties")
      expect(described_class.find("entry_page").scope.to_sym).to eq(:visit)
      expect(described_class.find("exit_page").sql.to_s).to include("dash_exits")
      expect(described_class.find("channel").scope.to_sym).to eq(:visit)
      expect(described_class.find("source").scope.to_sym).to eq(:visit)
      expect(described_class.find("device").sql.to_s).to include("device_type")
      expect(described_class.find("country").sql.to_s).to include("ahoy_visits.country")
    end

    it "reports a referrer folded rather than as ahoy stored it, and never our own host" do
      referrer = described_class.find("referrer")

      expect(referrer.sql.to_s).to eq(AhoyDashboard::Sql::REFERRER.to_s)
      expect(referrer.exclude.to_s).to eq(AhoyDashboard::Sql::INTERNAL_DOMAIN.to_s)
    end

    it "leaves a visit with no page view out of the entry dimensions" do
      %w[entry_page entry_url entry_host].each do |key|
        expect(described_class.find(key).exclude.to_s).to eq(AhoyDashboard::Sql::NEVER_VIEWED_A_PAGE)
      end
    end

    it "reads the page dimensions off page views only" do
      expect(described_class::ALL.select(&:page_views_only?).map(&:key)).to eq(%w[page page_group])
    end

    it "leaves every other dimension reporting everything it holds" do
      excluding = described_class::ALL.select(&:exclude).map(&:key)

      expect(excluding).to eq(%w[entry_page entry_url entry_host referrer])
    end

    it "carries the two dimensions read out of the landing page" do
      expect(described_class.find("entry_url").scope.to_sym).to eq(:visit)
      expect(described_class.find("entry_host").scope.to_sym).to eq(:visit)
      expect(described_class.find("entry_url").group).to eq("Page")
      expect(described_class.find("entry_host").group).to eq("Page")
    end

    it "raises for a key nobody registered" do
      expect { described_class.find("hairstyle") }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "hands back nil instead of raising from find_by_key" do
      expect(described_class.find_by_key("hairstyle")).to be_nil
      expect(described_class.find_by_key("page")).to eq(described_class.find("page"))
    end

    it "offers every filterable dimension to the filter dialog, and only those" do
      offered = described_class.filterable.map(&:key)

      expect(offered).to match_array(
        (described_class::ALL.select(&:filterable?) + described_class.registry.values).map(&:key)
      )
      expect(offered).not_to include("page_group")
      expect(described_class.find("page_group")).not_to be_filterable
    end

    it "adds the allowlisted properties to the filter dialog" do
      create(:dash_property, key: "facility_id")

      expect(described_class.filterable.map(&:key)).to include("prop:facility_id")
    end

    it "only names columns that exist on the ahoy tables" do
      columns = Ahoy::Visit.column_names

      described_class::ALL.each do |dimension|
        match = dimension.sql.to_s.match(/\Aahoy_visits\.(\w+)\z/)
        next if match.nil?

        expect(columns).to include(match[1]),
          "#{dimension.key} selects ahoy_visits.#{match[1]}, which is not a column"
      end
    end
  end

  describe ".register" do
    it "adds a dimension nobody wrote into ALL" do
      described_class.register(key: "widget", label: "Widget", group: "Behaviour", scope: :event,
                                sql: "ahoy_events.properties ->> 'widget'")

      expect(described_class.find("widget").label).to eq("Widget")
      expect(described_class.filterable.map(&:key)).to include("widget")
      expect(described_class.all.map(&:key)).to include("widget")
    end

    it "overwrites its own entry instead of raising, since to_prepare re-runs it on every reload" do
      described_class.register(key: "widget", label: "Widget", group: "Behaviour", scope: :event, sql: "null")
      described_class.register(key: "widget", label: "Renamed widget", group: "Behaviour", scope: :event,
                                sql: "null")

      expect(described_class.find("widget").label).to eq("Renamed widget")
    end

    it "refuses to alias a built-in key" do
      expect {
        described_class.register(key: "country", label: "Nope", group: "Behaviour", scope: :event, sql: "null")
      }.to raise_error(ArgumentError, /already built in/)
    end

    it "refuses to alias the goal key" do
      expect {
        described_class.register(key: "goal", label: "Nope", group: "Behaviour", scope: :event, sql: "null")
      }.to raise_error(ArgumentError, /already built in/)
    end

    it "refuses a key in the prop: namespace" do
      expect {
        described_class.register(key: "prop:widget", label: "Nope", group: "Behaviour", scope: :event, sql: "null")
      }.to raise_error(ArgumentError, /already built in/)
    end

    it "keeps a registered dimension out of the built-in registry" do
      described_class.register(key: "widget", label: "Widget", group: "Behaviour", scope: :event,
                                sql: "null")

      expect(described_class::ALL.map(&:key)).not_to include("widget")
      expect(described_class::INDEX).not_to have_key("widget")
      expect(described_class.all.map(&:key)).to include("widget")
    end
  end

  describe "the landing page dimensions" do
    def read(key, landing_page)
      create(:ahoy_visit, landing_page: landing_page)

      Ahoy::Visit.pluck(Arel.sql(described_class.find(key).sql.to_s)).first
    end

    it "keeps the query string on the url and takes it off the path" do
      url = "https://federalprisondude.com/search?q=halfway+house"

      expect(read("entry_url", url)).to eq(url)
      expect(read("entry_page", url)).to eq("/search")
    end

    it "reads the host, which the path drops entirely" do
      expect(read("entry_host", "https://portal.federalprisondude.com/vouch/cases"))
        .to eq("portal.federalprisondude.com")
      expect(read("entry_page", "https://portal.federalprisondude.com/vouch/cases"))
        .to eq("/vouch/cases")
    end

    it "drops the port, so the dev host groups with the production one" do
      expect(read("entry_host", "http://lvh.me:5000/resources")).to eq("lvh.me")
    end

    it "lower cases a host somebody typed in capitals" do
      expect(read("entry_host", "https://Federalprisondude.COM/")).to eq("federalprisondude.com")
    end

    it "reads nothing out of a landing page with no scheme on it" do
      expect(read("entry_host", "/resources")).to be_nil
      expect(read("entry_host", "")).to be_nil
    end

    it "reads nothing out of a visit that recorded no landing page" do
      expect(read("entry_url", nil)).to be_nil
      expect(read("entry_host", nil)).to be_nil
    end

    it "filters on a value without the question marks in it eating the bind" do
      create(:ahoy_visit, landing_page: "https://vouch.federalprisondude.com/quiet-harbor-8412?x=1")
      create(:ahoy_visit, landing_page: "https://federalprisondude.com/")

      %w[entry_url entry_host].each do |key|
        filter = AhoyDashboard::Filter.new(dimension: described_class.find(key), operator: "contains",
                                       value: "vouch")

        expect(filter.apply(Ahoy::Visit.all).count).to eq(1), "expected #{key} to filter cleanly"
      end
    end
  end

  describe ".goal" do
    it "groups to nothing when no goals are defined, rather than to broken sql" do
      expect(described_class.find("goal").sql.to_s).to eq("null::text")
    end

    it "builds a case expression over the defined goals" do
      create(:dash_goal, event_name: "site_searched")

      sql = described_class.find("goal").sql.to_s

      expect(sql).to include("ahoy_events.name = 'site_searched'")
      expect(sql).to include("then 'site_searched'")
    end

    it "picks up a goal added after the registry was loaded" do
      expect(described_class.find("goal").sql.to_s).to eq("null::text")

      create(:dash_goal, :pageview, path_pattern: "/thanks")

      expect(described_class.find("goal").sql.to_s).to include("/thanks")
    end
  end

  describe ".property" do
    it "builds an event dimension keyed under prop:" do
      dimension = described_class.property("facility_id")

      expect(dimension.key).to eq("prop:facility_id")
      expect(dimension.label).to eq("facility_id")
      expect(dimension.group).to eq("Behaviour")
      expect(dimension.scope.to_sym).to eq(:event)
      expect(dimension.sql.to_s).to include("ahoy_events.properties")
      expect(dimension.sql.to_s).to include("facility_id")
    end

    it "resolves through find" do
      expect(described_class.find("prop:facility_id").key).to eq("prop:facility_id")
    end

    it "reads the value back out of the events table" do
      visit = create(:ahoy_visit)
      create(:ahoy_event, visit: visit, name: "site_searched", time: Time.current,
                          properties: { "facility_id" => "42" })

      values = Ahoy::Event.pluck(Arel.sql(described_class.property("facility_id").sql.to_s))

      expect(values).to eq([ "42" ])
    end

    [
      "x'); drop table ahoy_events; --",
      "facility_id; drop table ahoy_events",
      "facility'id",
      "facility\"id",
      "path' or '1'='1",
      "properties ->> 'path'"
    ].each do |name|
      it "reads #{name.inspect} as nothing more than a key and leaves the table standing" do
        visit = create(:ahoy_visit)
        create(:ahoy_event, visit: visit, name: "site_searched", time: Time.current,
                            properties: { name => "hit", "path" => "/" })

        dimension = described_class.find("prop:#{name}")

        expect(Ahoy::Event.pluck(Arel.sql(dimension.sql.to_s))).to eq([ "hit" ])
        expect(ActiveRecord::Base.connection.table_exists?("ahoy_events")).to be(true)
        expect(Ahoy::Event.count).to eq(1)
      end
    end

    [ "", "  ", "line\nbreak", "tab\there", "a" * 256 ].each do |name|
      it "refuses the property name #{name.inspect}" do
        expect { described_class.property(name) }.to raise_error(ActiveRecord::RecordNotFound)
        expect { described_class.find("prop:#{name}") }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    it "accepts every name an app can send, spelled exactly" do
      [ "facility_id", "path_2", "CamelCase", "a", "facilityId", "utm-source", "page.section",
        "plan name", "a" * 255 ].each do |name|
        expect(described_class.find("prop:#{name}").key).to eq("prop:#{name}")
      end
    end

    it "matches a key by its exact spelling, capitals included" do
      visit = create(:ahoy_visit)
      create(:ahoy_event, visit: visit, name: "site_searched", time: Time.current,
                          properties: { "facilityId" => "42" })

      expect(Ahoy::Event.pluck(Arel.sql(described_class.property("facilityId").sql.to_s))).to eq([ "42" ])
      expect(Ahoy::Event.pluck(Arel.sql(described_class.property("facilityid").sql.to_s))).to eq([ nil ])
    end
  end

  describe ".grouped" do
    it "files the filterable dimensions under the filter dialog headings, in that order, each once" do
      groups = described_class.grouped

      expect(groups.map(&:first)).to start_with(*described_class::GROUPS)
      expect(groups.flat_map(&:last).map(&:key)).to eq(groups.flat_map(&:last).map(&:key).uniq)
    end

    it "takes the goal case along with the rest and lists it once" do
      groups = described_class.grouped(described_class.filterable + [ described_class.goal, described_class.goal ])

      expect(groups.flat_map(&:last).count { |dimension| dimension.key == described_class::GOAL_KEY }).to eq(1)
    end
  end

  describe ".collision" do
    it "finds the built in dimension a property name would be listed twice as" do
      expect(described_class.collision("format").key).to eq("format")
      expect(described_class.collision("Page format").key).to eq("format")
      expect(described_class.collision("facility_id")).to be_nil
    end

    it "keeps a colliding property out of the filter dialog" do
      AhoyDashboard::Property.new(key: "format").save(validate: false)

      expect(described_class.filterable.map(&:key)).to include("format")
      expect(described_class.filterable.map(&:key)).not_to include("prop:format")
    end
  end
end
