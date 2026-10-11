require "rails_helper"

RSpec.describe AhoyDashboard::Assets do
  around do |example|
    Dir.mktmpdir("dashboard-assets") do |directory|
      @asset_root = Pathname(directory)
      @asset_root.join("builds").mkpath
      @asset_root.join("fonts").mkpath
      @asset_root.join("builds/ahoy_dashboard.js").write("first")
      example.run
    end
  end

  before { allow(described_class).to receive(:root).and_return(@asset_root) }

  it "changes its URL when same-size content is replaced without changing the timestamp" do
    file = @asset_root.join("builds/ahoy_dashboard.js")
    before = described_class.build
    time = file.mtime
    file.write("other")
    File.utime(time, time, file)

    expect(described_class.build).not_to eq(before)
  end

  it "keeps its URL when deployment changes only file timestamps" do
    before = described_class.build
    file = @asset_root.join("builds/ahoy_dashboard.js")
    File.utime(Time.now + 60, Time.now + 60, file)

    expect(described_class.build).to eq(before)
  end

  it "keeps its URL when identical assets are installed at another path" do
    before = described_class.build
    relocated = @asset_root.join("relocated")
    relocated.join("builds").mkpath
    relocated.join("fonts").mkpath
    relocated.join("builds/ahoy_dashboard.js").write("first")
    allow(described_class).to receive(:root).and_return(relocated)

    expect(described_class.build).to eq(before)
  end
end
