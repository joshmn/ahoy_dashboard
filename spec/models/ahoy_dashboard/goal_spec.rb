require "rails_helper"

RSpec.describe AhoyDashboard::Goal do
  describe "validations" do
    it "wants an event name for a custom event goal" do
      goal = described_class.new(kind: :custom_event)

      expect(goal).not_to be_valid
      expect(goal.errors[:event_name]).to be_present
    end

    it "wants a path pattern for a pageview goal" do
      goal = described_class.new(kind: :pageview)

      expect(goal).not_to be_valid
      expect(goal.errors[:path_pattern]).to be_present
    end

    it "wants the path pattern to be a path" do
      goal = described_class.new(kind: :pageview, path_pattern: "resources")

      expect(goal).not_to be_valid
      expect(goal.errors[:path_pattern]).to include("has to start with a slash")
    end

    it "wants a value when a property key narrows the goal" do
      goal = described_class.new(kind: :custom_event, event_name: "x", property_key: "facility_id")

      expect(goal).not_to be_valid
      expect(goal.errors[:property_value]).to be_present
    end

    it "refuses a currency it does not know" do
      goal = described_class.new(kind: :custom_event, event_name: "x", currency: "XBT")

      expect(goal).not_to be_valid
    end

    # validate: true on the enum, so an unknown kind is a validation failure
    # rather than an ArgumentError raised at assignment.
    it "refuses a kind it does not know" do
      goal = described_class.new(kind: "guessing", event_name: "x")

      expect(goal).not_to be_valid
      expect(goal.errors[:kind]).to be_present
    end

    # The database index cannot catch this one, because the collision is between
    # a display_name and another goal's derived default.
    it "refuses a name another goal already resolves to" do
      described_class.create!(kind: :custom_event, event_name: "site_searched")
      clash = described_class.new(kind: :pageview, path_pattern: "/x", display_name: "site_searched")

      expect(clash).not_to be_valid
      expect(clash.errors[:base]).to include("another goal is already called site_searched")
    end

    it "lets a goal keep its own name on update" do
      goal = described_class.create!(kind: :custom_event, event_name: "site_searched")

      expect(goal.update(position: 4)).to be(true)
    end

    it "refuses the same definition twice at the database" do
      described_class.create!(kind: :custom_event, event_name: "site_searched")

      expect {
        described_class.new(kind: :custom_event, event_name: "site_searched", display_name: "Other").save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  it "rejects an explicit name colliding with another goal's derived name in the database" do
    create(:dash_goal, event_name: "booked")
    collision = build(:dash_goal, :pageview, path_pattern: "/booked", display_name: "booked")

    expect { collision.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "rejects a derived property name colliding with an explicit name in the database" do
    create(:dash_goal, event_name: "booked", display_name: "search (kind: consultation)")
    collision = build(:dash_goal, event_name: "search", property_key: "kind", property_value: "consultation")

    expect { collision.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe "#name" do
    it "uses the display name when there is one" do
      goal = described_class.new(kind: :custom_event, event_name: "x", display_name: "Something")

      expect(goal.name).to eq("Something")
    end

    it "falls back to the event name" do
      expect(described_class.new(kind: :custom_event, event_name: "site_searched").name).to eq("site_searched")
    end

    it "falls back to the path pattern" do
      expect(described_class.new(kind: :pageview, path_pattern: "/thanks").name).to eq("/thanks")
    end

    it "says which property variant it is" do
      goal = described_class.new(
        kind: :custom_event, event_name: "site_searched",
        property_key: "facility_id", property_value: "12"
      )

      expect(goal.name).to eq("site_searched (facility_id: 12)")
    end
  end

  describe "#match_sql" do
    it "matches an event by name" do
      goal = described_class.new(kind: :custom_event, event_name: "site_searched")

      expect(goal.match_sql).to eq("ahoy_events.name = 'site_searched'")
    end

    it "escapes a quote in the event name rather than breaking the query" do
      goal = described_class.new(kind: :custom_event, event_name: "it's")

      expect(goal.match_sql).to eq("ahoy_events.name = 'it''s'")
    end

    it "turns a star into a like wildcard" do
      goal = described_class.new(kind: :pageview, path_pattern: "/resources/*")

      expect(goal.match_sql).to include("like '/resources/%'")
    end

    it "escapes like metacharacters that appear in a real path" do
      goal = described_class.new(kind: :pageview, path_pattern: "/a_b/100%/*")

      expect(goal.match_sql).to include("like '/a\\_b/100\\%/%'")
    end

    it "adds the property condition when the goal is narrowed" do
      goal = described_class.new(
        kind: :custom_event, event_name: "site_searched",
        property_key: "facility_id", property_value: "12"
      )

      expect(goal.match_sql).to include("ahoy_events.properties ->> 'facility_id' = '12'")
    end
  end

  describe ".match_case_sql" do
    it "is nil when nothing is defined, so a caller can pick its own empty" do
      expect(described_class.match_case_sql).to be_nil
    end

    it "resolves to the goal name so a filter chip can read it back" do
      described_class.create!(kind: :custom_event, event_name: "x", display_name: "Did the thing")

      expect(described_class.match_case_sql).to include("then 'Did the thing'")
    end

    it "orders by position, so the first match wins in a chosen order" do
      described_class.create!(kind: :custom_event, event_name: "late", position: 5)
      described_class.create!(kind: :custom_event, event_name: "early", position: 1)

      sql = described_class.match_case_sql.to_s

      expect(sql.index("early")).to be < sql.index("late")
    end
  end

  it "reports whether it carries money" do
    expect(described_class.new(currency: "USD")).to be_revenue
    expect(described_class.new(currency: nil)).not_to be_revenue
  end

  it "trims blank strings to nil so a blank field is not a value" do
    goal = described_class.create!(kind: :custom_event, event_name: "  x  ", display_name: "   ")

    expect(goal.event_name).to eq("x")
    expect(goal.display_name).to be_nil
  end
end
