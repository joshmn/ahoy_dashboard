require "rails_helper"

RSpec.describe AhoyDashboard::SegmentDecorator, type: :decorator do
  describe "#dates" do
    it "names only the day it was made when nothing has changed since" do
      segment = travel_to(dash_time(2026, 4, 22, 9)) { create(:dash_segment) }

      expect(decorate(segment).dates).to eq("Created 22 Apr")
    end

    it "names both once it has been edited" do
      segment = travel_to(dash_time(2026, 4, 22, 9)) { create(:dash_segment) }
      travel_to(dash_time(2026, 8, 3, 9)) { segment.update!(name: "Renamed") }

      expect(decorate(segment).dates).to eq("Created 22 Apr, last updated 3 Aug")
    end

    it "reads the dates in the dashboard's own zone" do
      segment = travel_to(dash_time(2026, 4, 22, 23, 30)) { create(:dash_segment) }

      expect(decorate(segment).dates).to eq("Created 22 Apr")
    end
  end

  describe "#meta" do
    it "says the kind and the dates" do
      segment = travel_to(dash_time(2026, 4, 22, 9)) { create(:dash_segment) }

      expect(decorate(segment).meta).to eq("Site segment. Created 22 Apr")
    end

    it "says why instead of the dates when it cannot be read" do
      segment = create(:dash_segment, :unreadable)

      expect(decorate(segment).meta).to include("Not being applied")
    end
  end

  describe "#summary" do
    it "reads the filters out in words" do
      segment = create(:dash_segment, filters: [
        { "dimension" => "country", "operator" => "is_not", "value" => "US" },
        { "dimension" => "browser", "operator" => "is", "value" => "Chrome" }
      ])

      expect(decorate(segment.reload).summary).to eq("Country is not US and Browser is Chrome")
    end

    it "reads an or group as or, bracketed apart from the rest" do
      segment = create(:dash_segment, filters: [
        { "dimension" => "country", "operator" => "is", "value" => "US", "group" => 0 },
        { "dimension" => "country", "operator" => "is", "value" => "CA", "group" => 0 },
        { "dimension" => "browser", "operator" => "is", "value" => "Chrome" }
      ])

      expect(decorate(segment.reload).summary).to eq("(Country is US or CA) and Browser is Chrome")
    end

    it "says it cannot be read rather than reading out nothing" do
      segment = create(:dash_segment, :unreadable)

      expect(decorate(segment).summary).to include("cannot read")
    end
  end

  describe "#count_label" do
    it "counts the filters" do
      expect(decorate(create(:dash_segment)).count_label).to eq("1 filter")
    end
  end
end
