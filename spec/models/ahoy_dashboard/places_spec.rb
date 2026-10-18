require "rails_helper"

RSpec.describe AhoyDashboard::Places do
  def switch(on)
    AhoyDashboard::Preferences.write(:places, enabled: on)
    yield
  end

  describe ".source_url" do
    it "names the file for the month" do
      expect(described_class.source_url(Date.new(2026, 9, 1)))
        .to eq("https://cdn.dataforseo.com/v3/locations/locations_serp_google_2026_09_01.csv")
    end
  end

  describe ".ready?" do
    it "is false with the feature off, whatever is in the table" do
      create(:dash_place)

      expect(described_class).not_to be_ready
    end

    it "is false with the feature on and nothing built" do
      switch(true) { expect(described_class).not_to be_ready }
    end

    it "is true once there is something to pick from" do
      create(:dash_place)

      switch(true) { expect(described_class).to be_ready }
    end
  end

  describe ".note" do
    it "says it is off, and that nothing changes because of it" do
      expect(described_class.note).to include("Off")
    end

    it "says what to do when it is on and empty" do
      switch(true) { expect(described_class.note).to include("Run it once") }
    end

    it "says how many places there are and when they were read" do
      create(:dash_place, synced_at: dash_time(2026, 9, 2, 3, 0))

      switch(true) { expect(described_class.note).to include("1 places", "September 2, 2026") }
    end
  end
end
