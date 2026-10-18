require "rails_helper"
require AhoyDashboard::Engine.root.join("lib/ahoy_dashboard/asset_manifest").to_s

RSpec.describe "AhoyDashboard packaging" do
  let(:root) { AhoyDashboard::Engine.root }
  let(:gemspec) { Gem::Specification.load(root.join("ahoy_dashboard.gemspec").to_s) }
  let(:entrypoint) { root.join("lib/ahoy_dashboard.rb").read }

  it "requires every runtime dependency from its entrypoint" do
    required = entrypoint.scan(/^require "([^"]+)"/).flatten

    gemspec.runtime_dependencies.map(&:name).each do |gem_name|
      next if gem_name == "rails"

      expect(required).to include(gem_name),
        "#{gem_name} is a runtime dependency but lib/ahoy_dashboard.rb never requires it"
    end
  end

  it "ships the front end it serves" do
    packaged = gemspec.files

    expect(packaged).to include("assets/builds/ahoy_dashboard.css")
    expect(packaged).to include("assets/builds/ahoy_dashboard.js")
    expect(packaged).to include("assets/builds/ahoy_dashboard.js.map")
    expect(packaged.grep(%r{\Aassets/fonts/.*\.woff2\z})).not_to be_empty
  end

  it "ships the script compiled from its current sources" do
    expect(AhoyDashboard::AssetManifest.new(root: root).current?(kind: "javascript")).to be(true)
  end

  it "ships the stylesheet compiled from its current sources" do
    expect(AhoyDashboard::AssetManifest.new(root: root).current?(kind: "stylesheet")).to be(true)
  end

  it "asks for at least the Rails its migrations are written for" do
    versions = root.glob("db/migrate/**/*.rb").map { |file| file.read[/ActiveRecord::Migration\[(\d+\.\d+)\]/, 1] }.compact
    rails = gemspec.runtime_dependencies.find { |dependency| dependency.name == "rails" }

    expect(versions).not_to be_empty
    versions.uniq.each do |version|
      expect(rails.requirement.requirements).to all(satisfy { |_op, floor| floor >= Gem::Version.new(version) })
    end
  end

  it "declares csv, which it requires and which Ruby no longer bundles" do
    expect(gemspec.runtime_dependencies.map(&:name)).to include("csv")
  end

  it "ships the docs the README links to" do
    links = root.join("README.md").read.scan(/\]\((docs\/[^)#\s]+)/).flatten.uniq

    expect(links).not_to be_empty
    expect(gemspec.files).to include(*links)
    expect(gemspec.files).to include(*root.glob("docs/**/*.md").map { |file| file.relative_path_from(root).to_s })
  end

  it "serves the files it ships" do
    expect(AhoyDashboard::Assets.files.map { |file| file.basename.to_s })
      .to include("ahoy_dashboard.css", "ahoy_dashboard.js")
    expect(AhoyDashboard::Assets.files).to all(exist)
  end
end
