require "rails_helper"

RSpec.describe AhoyDashboard::Preferences do
  it "disables precomputed dashboard snapshots until enabled in settings" do
    expect(described_class.read(:site, :precomputed_dashboard)).to eq(false)
  end

  it "answers the default for anything never saved" do
    expect(described_class.read(:keywords, :location)).to eq("us")
    expect(described_class.read(:site, :internal_ips)).to eq(described_class::INTERNAL_IPS)
    expect(described_class.read(:alerts, :send_empty)).to be(true)
    expect(described_class.read(:reports, :digest)).to eq([])
    expect(described_class.read(:site, :canonical_host)).to be_nil
  end

  it "casts what it saves to the setting's type" do
    described_class.write(:alerts, digest: "weekly, Daily, hourly", recipients: "a@example.com\nb@example.com, a@example.com",
                                   send_empty: "0")
    described_class.write(:keywords, provider: "dataforseo")
    described_class.write(:places, postal_codes: "1")

    expect(described_class.read(:alerts, :digest)).to eq(%i[daily weekly])
    expect(described_class.read(:alerts, :recipients)).to eq([ "a@example.com", "b@example.com" ])
    expect(described_class.read(:alerts, :send_empty)).to be(false)
    expect(described_class.read(:keywords, :provider)).to eq(:dataforseo)
    expect(described_class.read(:places, :postal_codes)).to be(true)
  end

  it "keeps an emptied list rather than falling back to the default" do
    described_class.write(:site, internal_ips: "")

    expect(described_class.read(:site, :internal_ips)).to eq([])
    expect(described_class.stored?(:site, :internal_ips)).to be(true)
  end

  it "goes back to the default when a value is blanked or cleared" do
    described_class.write(:keywords, location: "gb", language: "fr")
    described_class.write(:keywords, location: "")
    described_class.clear(:keywords, :language)

    expect(described_class.read(:keywords, :location)).to eq("us")
    expect(described_class.read(:keywords, :language)).to eq("en")
    expect(described_class.stored?(:keywords, :location)).to be(false)
  end

  it "keeps the time zone under the key it has always had" do
    described_class.write(:site, time_zone: "Tokyo")

    expect(AhoyDashboard::Setting.read(AhoyDashboard::Setting::TIME_ZONE)).to eq("Tokyo")
    expect(AhoyDashboard.time_zone.name).to eq("Tokyo")
  end

  it "reads every setting once per request and forgets on a write" do
    described_class.read(:site, :host)
    AhoyDashboard::Setting.write("site.host", "elsewhere.test")
    expect(described_class.read(:site, :host)).to eq("example.com")

    described_class.write(:site, canonical_host: "www.example.com")
    expect(described_class.read(:site, :host)).to eq("elsewhere.test")
  end

  it "refuses a setting it does not know" do
    expect { described_class.read(:site, :colour) }.to raise_error(ArgumentError, "no setting named colour for site")
  end
end
