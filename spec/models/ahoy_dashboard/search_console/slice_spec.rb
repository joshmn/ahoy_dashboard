require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::Slice do
  def slice(**params)
    described_class.from_params(params)
  end

  it "reads as the whole site when nothing is picked" do
    expect(slice).not_to be_any
    expect(slice.device_label).to eq("All devices")
    expect(slice.country_label).to eq("All countries")
    expect(slice.to_query).to eq({})
  end

  it "takes a device and a country in any case" do
    picked = slice(device: "Mobile", country: "USA")

    expect(picked.to_query).to eq(device: "mobile", country: "usa")
    expect(picked.device_label).to eq("Mobile")
    expect(picked.country_label).to eq("United States")
  end

  it "ignores a device google does not report and a country that is not a three letter code" do
    expect(slice(device: "phone", country: "us").to_query).to eq({})
    expect(slice(device: "desktop", country: "u'sa").to_query).to eq(device: "desktop")
  end

  it "narrows a relation to its device and country, leaving the older unsliced rows out" do
    create(:dash_search_console_total, date: Date.new(2026, 8, 3), device: "mobile", country: "usa", clicks: 4)
    create(:dash_search_console_total, date: Date.new(2026, 8, 3), device: "desktop", country: "usa", clicks: 2)
    create(:dash_search_console_total, date: Date.new(2026, 8, 2), clicks: 9)

    expect(slice.apply(AhoyDashboard::SearchConsoleTotal.all).sum(:clicks)).to eq(15)
    expect(slice(device: "mobile").apply(AhoyDashboard::SearchConsoleTotal.all).sum(:clicks)).to eq(4)
    expect(slice(country: "usa").apply(AhoyDashboard::SearchConsoleTotal.all).sum(:clicks)).to eq(6)
  end

  it "swaps one side and keeps the other" do
    picked = slice(device: "mobile", country: "usa").with(device: nil)

    expect(picked.to_query).to eq(country: "usa")
    expect(picked).to eq(slice(country: "usa"))
  end

  describe "narrowing visits" do
    let(:started) { Time.zone.local(2026, 8, 3, 12) }

    def visit(device_type:, country:)
      Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: SecureRandom.uuid,
                          started_at: started, device_type: device_type, country: country)
    end

    it "matches the device whatever case ahoy stored it in, and the country by its two letter code" do
      visit(device_type: "Desktop", country: "US")
      visit(device_type: "desktop", country: "US")
      visit(device_type: "desktop", country: "CA")
      visit(device_type: "mobile", country: "US")

      narrowed = slice(device: "desktop", country: "usa").visits(Ahoy::Visit.all)

      expect(narrowed.count).to eq(2)
    end

    it "matches a visit whose country was stored as a full name" do
      visit(device_type: "mobile", country: "United States")

      expect(slice(country: "usa").visits(Ahoy::Visit.all).count).to eq(1)
    end
  end
end
