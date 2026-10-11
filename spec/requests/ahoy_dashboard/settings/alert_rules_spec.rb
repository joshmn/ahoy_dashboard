require "rails_helper"

RSpec.describe "Dashboard alert rule settings", type: :request do
  def document
    Nokogiri::HTML5(response.body)
  end

  before { sign_in create(:user, :admin) }

  it "is a 404 for a signed in visitor who is not an admin" do
    sign_out :user
    sign_in create(:user)

    get "/telemetry/settings/alert_rules"

    expect(response).to have_http_status(:not_found)
  end

  it "lists every rule under its group" do
    AhoyDashboard::Alerts::Rules::InstallCommand.call
    get "/telemetry/settings/alert_rules"

    tables = document.css("[role=group][aria-label]").map do |group|
      [ group["aria-label"], group.css("tbody tr td:first-child a[href$='/edit']").map { |link| link.text.squish } ]
    end.to_h

    expect(tables).to eq(
      "Rank tracking alert rules" => AhoyDashboard::AlertRule.ordered.select { |rule| rule.group == :rank }.map(&:name),
      "Spending alert rules" => [ "Nearing the monthly cap" ],
      "Search Console alert rules" => [ "Search clicks fell", "Impressions fell" ],
      "Goals alert rules" => [ "Goal stopped converting", "Goal conversions fell" ],
      "Backlinks alert rules" => [ "Referring domains lost" ],
      "Jobs alert rules" => [ "A job failed", "A job stopped running" ],
      "Traffic alert rules" => [ "Traffic drop", "Traffic spike" ]
    )
  end

  it "says the traffic rules need 28 days of visits until there are 28 days of them" do
    AhoyDashboard::Alerts::Rules::InstallCommand.call
    create(:ahoy_visit, started_at: 10.days.ago)

    get "/telemetry/settings/alert_rules"

    traffic = document.at_css("[aria-label='Traffic alert rules']").text.squish
    jobs = document.at_css("[aria-label='Jobs alert rules']").text.squish
    expect(traffic.scan("Needs 28 days of visits").size).to eq(2)
    expect(jobs).not_to include("Needs 28 days of visits")
  end

  it "drops the note once there are 28 days of visits" do
    AhoyDashboard::Alerts::Rules::InstallCommand.call
    create(:ahoy_visit, started_at: 40.days.ago)

    get "/telemetry/settings/alert_rules"

    expect(document.text).not_to include("Needs 28 days of visits")
  end

  it "does not install rules when the settings page is read" do
    expect { get "/telemetry/settings/alert_rules" }.not_to change(AhoyDashboard::AlertRule, :count)
  end

  it "does not remove historical events when the settings page is read" do
    rule = build(:dash_alert_rule, key: "retired_rule")
    rule.save!(validate: false)
    event = create(:dash_alert_event, rule: rule)

    get "/telemetry/settings/alert_rules"

    expect(event.reload.rule).to eq(rule)
  end

  it "asks for a floor on a traffic rule and nowhere else" do
    AhoyDashboard::Alerts::Rules::InstallCommand.call
    spike = AhoyDashboard::AlertRule.find_by!(key: "traffic_spike")
    fell = AhoyDashboard::AlertRule.find_by!(key: "search_clicks_fell")

    get "/telemetry/settings/alert_rules/#{spike.id}/edit"

    expect(document.at_css("label[for='alert_rule_floor']").text.squish).to eq("Floor")
    expect(document.at_css("#alert_rule_floor")["placeholder"]).to eq("20")
    expect(document.at_css("label[for='alert_rule_threshold']").text.squish).to eq("Times the usual")

    get "/telemetry/settings/alert_rules/#{fell.id}/edit"

    expect(document.at_css("#alert_rule_floor")).to be_nil
  end

  it "saves a floor" do
    AhoyDashboard::Alerts::Rules::InstallCommand.call
    rule = AhoyDashboard::AlertRule.find_by!(key: "traffic_drop")

    patch "/telemetry/settings/alert_rules/#{rule.id}", params: { alert_rule: { floor: "250" } }

    expect(response).to redirect_to("/telemetry/settings/alert_rules")
    expect(rule.reload.floor).to eq(250)
    expect(rule.condition).to end_with("and the usual is at least 250")
  end

  it "refuses a negative floor" do
    AhoyDashboard::Alerts::Rules::InstallCommand.call
    rule = AhoyDashboard::AlertRule.find_by!(key: "traffic_drop")

    patch "/telemetry/settings/alert_rules/#{rule.id}", params: { alert_rule: { floor: "-1" } }

    expect(response).to have_http_status(422)
    expect(rule.reload.floor).to eq(100)
  end

  it "asks for a percent on a rule that reads one" do
    AhoyDashboard::Alerts::Rules::InstallCommand.call
    rule = AhoyDashboard::AlertRule.find_by!(key: "search_clicks_fell")

    get "/telemetry/settings/alert_rules/#{rule.id}/edit"

    expect(document.at_css("label[for='alert_rule_threshold']").text.squish).to eq("Percent")
    expect(document.text.squish).to include("Fires when clicks over the last 7 finished days are down 30% or more")
  end

  it "has no threshold on a rule that reads none" do
    AhoyDashboard::Alerts::Rules::InstallCommand.call
    rule = AhoyDashboard::AlertRule.find_by!(key: "job_failed")

    get "/telemetry/settings/alert_rules/#{rule.id}/edit"

    expect(document.at_css("#alert_rule_threshold")).to be_nil
  end

  it "switches a rule on and sets its threshold" do
    AhoyDashboard::Alerts::Rules::InstallCommand.call
    rule = AhoyDashboard::AlertRule.find_by!(key: "goal_conversions_fell")

    patch "/telemetry/settings/alert_rules/#{rule.id}", params: { alert_rule: { enabled: "true", threshold: "50", severity: "high" } }

    expect(response).to redirect_to("/telemetry/settings/alert_rules")
    expect(rule.reload).to have_attributes(enabled: true, threshold: 50, severity: "high")
  end

  describe "a threshold the rule cannot use" do
    before { AhoyDashboard::Alerts::Rules::InstallCommand.call }

    {
      "big_drop" => %w[0 -3 100 2.5],
      "off_page_one" => %w[0 -1 100],
      "search_clicks_fell" => %w[0 101],
      "backlinks_lost" => %w[0],
      "traffic_spike" => %w[1 0],
      "traffic_drop" => %w[-1 100]
    }.each do |key, values|
      values.each do |value|
        it "refuses #{value} on #{key} and says what it takes" do
          rule = AhoyDashboard::AlertRule.find_by!(key: key)
          before = rule.threshold

          patch "/telemetry/settings/alert_rules/#{rule.id}", params: { alert_rule: { threshold: value } }

          expect(response).to have_http_status(422)
          expect(rule.reload.threshold).to eq(before)
          expect(document.at_css("#alert_rule_threshold")["aria-invalid"]).to eq("true")
        end
      end
    end

    it "says the range on the edit screen and on the field" do
      rule = AhoyDashboard::AlertRule.find_by!(key: "big_drop")

      get "/telemetry/settings/alert_rules/#{rule.id}/edit"

      field = document.at_css("#alert_rule_threshold")
      expect(field.attributes.slice("min", "max").transform_values(&:value)).to eq("min" => "1", "max" => "99")
      expect(document.text.squish).to include("Use a whole number from 1 to 99.")
    end

    it "saves the edges of the range" do
      rule = AhoyDashboard::AlertRule.find_by!(key: "traffic_drop")

      patch "/telemetry/settings/alert_rules/#{rule.id}", params: { alert_rule: { threshold: "0" } }

      expect(rule.reload.threshold).to eq(0)
    end

    it "runs a rule saved before thresholds were checked on its default rather than the bad number" do
      rule = AhoyDashboard::AlertRule.find_by!(key: "big_drop")
      rule.update_columns(threshold: 0)

      expect(rule.reload.threshold_value).to eq(5)
      expect(rule.condition).to eq("a search falls by 5 places or more between checks")
    end
  end
end
