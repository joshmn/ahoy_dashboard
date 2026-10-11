require "rails_helper"
require "rake"
require "support/ahoy_dashboard/serp"
require "support/ahoy_dashboard/installation"

RSpec.describe "ahoy_dashboard serp tasks" do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { AhoyDashboard.time_zone.local(2026, 8, 20, 9, 0) }

  around { |example| travel_to(now) { example.run } }

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("ahoy_dashboard:serp_search")
  end

  def run(name, *args)
    task = Rake::Task[name]
    task.reenable
    output = StringIO.new
    original = $stdout
    $stdout = output
    begin
      task.invoke(*args)
    ensure
      $stdout = original
    end
    output.string
  end

  describe "serp" do
    it "points at the settings screen when no provider is saved" do
      stub_const("ENV", ENV.to_h.merge("SERPAPI_KEY" => "from-env"))

      printed = run("ahoy_dashboard:serp")

      expect(printed).to include("provider: fake", "serpapi: no credentials")
      expect(printed).to include("pick a real provider under settings, search provider, and save its key")
      expect(printed).not_to include("config.")
    end
  end

  describe "serp_search" do
    let!(:provider) do
      create(:dash_serp_provider, :serpapi, :active, monthly_cap_units: 10, units_spent: 3,
                                                     units_reset_on: now.to_date.beginning_of_month)
    end

    before { serpapi_configured! }

    it "refuses while serp tracking is switched off" do
      search = stub_serpapi(body: serpapi_body(organic: serpapi_organic("https://bop.gov/a")))

      expect { run("ahoy_dashboard:serp_search", "visiting hours") }
        .to raise_error(SystemExit).and output(/switched off/).to_stderr

      expect(search).not_to have_been_requested
    end

    it "refuses at the monthly ceiling" do
      serp_enabled!(provider: :serpapi)
      provider.update!(units_spent: 10)
      search = stub_serpapi(body: serpapi_body(organic: serpapi_organic("https://bop.gov/a")))

      expect { run("ahoy_dashboard:serp_search", "visiting hours") }
        .to raise_error(SystemExit).and output(/ceiling/).to_stderr

      expect(search).not_to have_been_requested
      expect(provider.reload.spent_this_month).to eq(10)
    end

    it "counts what it spent against the provider" do
      serp_enabled!(provider: :serpapi)
      stub_serpapi(body: serpapi_body(organic: serpapi_organic("https://bop.gov/a")))

      printed = run("ahoy_dashboard:serp_search", "visiting hours")

      expect(printed).to include("bop.gov")
      expect(provider.reload.spent_this_month).to eq(4)
    end
  end

  describe "serp_check" do
    let(:site) { create(:dash_serp_site, domain: "example.com") }
    let(:keyword) { create(:dash_serp_keyword, query: "visiting hours") }

    before do
      serp_enabled!
      create(:dash_serp_keyword_target, keyword: keyword, site: site)
    end

    it "does not check a paused keyword" do
      keyword.update!(enabled: false)

      printed = run("ahoy_dashboard:serp_check", "visiting hours")

      expect(printed).to include("skipped: this keyword is paused")
      expect(AhoyDashboard::SerpRun.count).to be_zero
    end

    it "does not search for a keyword with no site" do
      AhoyDashboard::SerpKeywordTarget.delete_all

      printed = run("ahoy_dashboard:serp_check", "visiting hours")

      expect(printed).to include("skipped: this keyword has no site to look for")
      expect(AhoyDashboard::SerpRun.count).to be_zero
    end
  end

  describe "with rank tracking not installed" do
    let(:line) do
      "rank tracking is not installed. run bin/rails generate ahoy_dashboard:install " \
        "--only serp, then bin/rails db:migrate\n"
    end

    before { uninstall_ahoy_dashboard(:serp) }

    it "prints one line saying how to install it from every serp task" do
      expect(run("ahoy_dashboard:serp")).to eq(line)
      expect(run("ahoy_dashboard:serp_backfill_results")).to eq(line)
      expect(run("ahoy_dashboard:serp_check", "visiting hours")).to eq(line)
      expect(run("ahoy_dashboard:serp_search", "visiting hours")).to eq(line)
    end
  end

  describe "the alert and backlink tasks with their tables not installed" do
    before { uninstall_ahoy_dashboard(:alerts, :backlinks, :keywords) }

    it "prints one line each and touches nothing" do
      expect(run("ahoy_dashboard:alert_rules")).to start_with("alerts is not installed. run").and(include("--only alerts"))
      expect(run("ahoy_dashboard:alerts")).to start_with("alerts is not installed")
      expect(run("ahoy_dashboard:backlinks")).to include("--only backlinks")
      expect(run("ahoy_dashboard:keywords", "federal prison")).to include("--only keywords")
    end
  end

  describe "alert_rules with a source not installed" do
    before { uninstall_ahoy_dashboard(:serp) }

    it "still lists the rank rules and says how to install what they need" do
      printed = run("ahoy_dashboard:alert_rules")

      expect(printed).to include("off_page_one").and(include("job_failed"))
      expect(sole_item(printed.lines.grep(/off_page_one/)))
        .to include("cannot run until rank tracking is installed. run bin/rails generate ahoy_dashboard:install --only serp")
      expect(sole_item(printed.lines.grep(/job_failed/))).not_to include("cannot run")
    end
  end
end
