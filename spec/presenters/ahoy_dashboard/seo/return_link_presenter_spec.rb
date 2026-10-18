require "rails_helper"

RSpec.describe AhoyDashboard::Seo::ReturnLinkPresenter do
  let(:surface) { AhoyDashboard::Seo::Surface.find("opportunities") }
  let(:options) do
    { host: "example.com", path: "/telemetry/search_console_keyword", referer: nil, remembered: nil,
      fallback_label: "Performance", fallback_url: "/telemetry/search_console_report" }
  end

  it "returns to the originating SEO report with its filters" do
    presenter = described_class.new(**options.merge(referer: "http://example.com#{surface.path}?period=7d"))

    expect(presenter.url).to eq("#{surface.path}?period=7d")
  end

  it "ignores a referer from another host" do
    presenter = described_class.new(**options.merge(referer: "https://elsewhere.test#{surface.path}"))

    expect(presenter.url).to eq(options.fetch(:fallback_url))
  end

  it "retains the originating report while changing the current keyword range" do
    remembered = { "page" => options.fetch(:path), "key" => surface.key, "url" => surface.path }
    presenter = described_class.new(**options.merge(remembered: remembered, referer: "http://example.com#{options.fetch(:path)}?period=7d"))

    expect(presenter.key).to eq(surface.key)
  end
end
