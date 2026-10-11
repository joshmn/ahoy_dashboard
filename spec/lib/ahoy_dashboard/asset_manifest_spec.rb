require "rails_helper"
require AhoyDashboard::Engine.root.join("lib/ahoy_dashboard/asset_manifest").to_s

RSpec.describe AhoyDashboard::AssetManifest do
  around do |example|
    Dir.mktmpdir("dashboard-build") do |directory|
      @root = Pathname(directory)
      @root.join("assets/javascript").mkpath
      @root.join("assets/builds").mkpath
      @root.join("assets/javascript/index.js").write("first")
      @root.join("assets/builds/ahoy_dashboard.js").write("built")
      @root.join("assets/builds/ahoy_dashboard.js.map").write("{}")
      @root.join("Rakefile").write("build")
      @manifest = described_class.new(root: @root)
      @manifest.record(kind: "javascript", compiler: "test")
      example.run
    end
  end

  it "recognizes the recorded source and output content" do
    expect(@manifest.current?(kind: "javascript")).to be(true)
  end

  it "detects a changed source even when its timestamp was preserved" do
    file = @root.join("assets/javascript/index.js")
    time = file.mtime
    file.write("other")
    File.utime(time, time, file)

    expect(@manifest.current?(kind: "javascript")).to be(false)
  end

  it "detects changes to the bundled output" do
    @root.join("assets/builds/ahoy_dashboard.js").write("other")

    expect(@manifest.current?(kind: "javascript")).to be(false)
  end
end
