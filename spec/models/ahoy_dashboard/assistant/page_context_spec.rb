require "rails_helper"

RSpec.describe AhoyDashboard::Assistant::PageContext do
  def context(path, params = {})
    described_class.call(path: path, query: AhoyDashboard::QueryForm.from_params(params))
  end

  it "names the screen a path belongs to" do
    expect(context("/telemetry/rankings")["screen"]).to eq("rankings")
    expect(context("/telemetry/rankings")["does"]).to include("results page")
  end

  # Every telemetry path starts with the dashboard's, so the longest match has
  # to win or a settings screen reads as the dashboard.
  it "does not read a settings screen as the dashboard" do
    expect(context("/telemetry/settings/serp_keywords")["screen"]).to eq("rank tracking")
  end

  it "reads the screen off a path that carries a query string" do
    expect(context("/telemetry/explore?period=7d")["screen"]).to eq("explore")
  end

  it "reads the dashboard's own path as the dashboard" do
    expect(context("/telemetry/dashboard?metric=pageviews&period=30d")["screen"]).to eq("dashboard")
  end

  it "does not read an SEO surface as the SEO overview" do
    expect(context("/telemetry/seo/serp_feature?period=30d")["screen"]).to eq("SERP features")
    expect(context("/telemetry/seo?period=30d")["screen"]).to eq("SEO")
  end

  it "says nothing about a screen it does not know" do
    expect(context("/telemetry/nowhere")).not_to have_key("screen")
  end

  it "leaves the query string out of the line for a screen it does not know" do
    read = context("/telemetry/nowhere?metric=pageviews", period: "7d")

    expect(described_class.line(read)).to eq("/telemetry/nowhere, Last 7 days")
  end

  it "carries the window and the filters" do
    read = context("/telemetry", period: "7d",
                   filters: [ { dimension: "country", operator: "is", value: "US" } ])

    expect(read["window"]).to eq("Last 7 days")
    expect(read["filters"]).to eq([ "Country is US" ])
    expect(read["crawlers"]).to eq("excluded")
  end

  it "names a filter on a withheld dimension without its value" do
    AhoyDashboard::Setting.write(AhoyDashboard::Assistant::WITHHELD_KEY, %w[city])
    read = context("/telemetry", period: "7d", filters: [ { dimension: "city", operator: "is", value: "Springfield" } ])

    expect(read["filters"]).to eq([ "City, kept out of the assistant" ])
  end

  describe "or groups" do
    let(:grouped) do
      [ { dimension: "country", operator: "is", value: "US", group: "0" },
        { dimension: "country", operator: "is", value: "CA", group: "0" },
        { dimension: "page", operator: "is", value: "/pricing" } ]
    end

    it "labels each group once, with or inside it and brackets around it" do
      read = context("/telemetry", period: "7d", filters: grouped)

      expect(read["filters"]).to eq([ "(Country is US or CA)", "Page is /pricing" ])
      expect(described_class.line(read)).to eq("dashboard, Last 7 days, filtered to (Country is US or CA) and Page is /pricing")
    end

    it "needs no brackets when the group is the only one" do
      read = context("/telemetry", period: "7d", filters: grouped.first(2))

      expect(read["filters"]).to eq([ "Country is US or CA" ])
    end

    it "names a withheld dimension inside a group without any of its values" do
      AhoyDashboard::Setting.write(AhoyDashboard::Assistant::WITHHELD_KEY, %w[city])
      read = context("/telemetry", period: "7d", filters: [
        { dimension: "city", operator: "is", value: "Springfield", group: "0" },
        { dimension: "city", operator: "is", value: "Shelbyville", group: "0" },
        { dimension: "country", operator: "is", value: "CA", group: "0" }
      ])

      expect(read["filters"]).to eq([ "Country is CA or City, kept out of the assistant" ])
      expect(read["filters"].join).not_to include("Springfield")
      expect(read["filters"].join).not_to include("Shelbyville")
    end

    it "saves the group numbers in the slice" do
      read = context("/telemetry", period: "7d", filters: grouped)

      expect(read["slice"]["filters"].map { |entry| entry["group"] }).to eq([ 0, 0, nil ])
    end
  end

  describe "hidden traffic" do
    it "says it is excluded and names what hides it" do
      AhoyDashboard::Exclusion.create!(name: "Datacenters",
                                       filters: [ { "dimension" => "asn", "operator" => "contains", "value" => "AMAZON" } ])
      AhoyDashboard::Exclusion.create!(name: "Switched off", enabled: false,
                                       filters: [ { "dimension" => "country", "operator" => "is", "value" => "FR" } ])
      read = context("/telemetry", period: "7d")

      expect(read["hidden_traffic"]).to eq("excluded")
      expect(read["hidden_by"]).to include("Datacenters")
      expect(read["hidden_by"]).not_to include("Switched off")
      expect(read.to_s).not_to include("AMAZON")
      expect(read).not_to have_key("internal_addresses")
    end

    it "says it is shown when the screen shows it, and names nothing" do
      AhoyDashboard::Exclusion.create!(name: "Datacenters",
                                       filters: [ { "dimension" => "asn", "operator" => "contains", "value" => "AMAZON" } ])
      read = context("/telemetry", period: "7d", internal: "1")

      expect(read["hidden_traffic"]).to eq("shown")
      expect(read).not_to have_key("hidden_by")
    end
  end

  it "saves the filters themselves alongside their labels" do
    read = context("/telemetry", period: "7d", crawlers: "1",
                   filters: [ { dimension: "country", operator: "is", value: "US" } ])

    expect(read["slice"]).to eq("filters" => [ { "dimension" => "country", "operator" => "is", "value" => "US" } ],
                                "crawlers" => true, "internal" => false)
  end

  it "writes one line out of what it read" do
    read = context("/telemetry", period: "7d",
                   filters: [ { dimension: "country", operator: "is", value: "US" } ])

    expect(described_class.line(read)).to eq("dashboard, Last 7 days, filtered to Country is US")
  end

  it "writes no line for a chat that was not started from a page" do
    expect(described_class.line({})).to be_nil
  end
end
