require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsole::PropertyForm do
  let(:sites) do
    [
      AhoyDashboard::SearchConsole::SitesService::Site.new(url: "sc-domain:example.com", permission: "siteOwner"),
      AhoyDashboard::SearchConsole::SitesService::Site.new(url: "https://www.example.com/", permission: "siteOwner")
    ]
  end

  it "offers every property Google listed, marking the domain ones" do
    form = described_class.new(sites: sites)

    expect(form.property_options).to eq([
      [ "example.com (domain)", "sc-domain:example.com" ],
      [ "https://www.example.com/", "https://www.example.com/" ]
    ])
  end

  it "accepts one of the properties Google listed and refuses anything else" do
    expect(described_class.new(sites: sites, property_uri: "https://www.example.com/")).to be_valid

    form = described_class.new(sites: sites, property_uri: "https://typed.example/")
    expect(form).not_to be_valid
    expect(form.errors[:property_uri]).to eq([ "That property is not one Google says this account can read." ])
  end

  it "has nothing to offer and nothing to check against when Google listed nothing" do
    form = described_class.new(property_uri: "https://typed.example/")

    expect(form.property_options).to eq([])
    expect(form).to be_valid
  end
end
