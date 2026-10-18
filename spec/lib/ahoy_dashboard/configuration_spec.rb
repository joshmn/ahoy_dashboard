require "rails_helper"

RSpec.describe AhoyDashboard::Configuration do
  subject(:config) { described_class.new }

  it "leaves the embedded scheduler off by default" do
    expect(config.embedded_scheduler).to be(false)
  end

  it "keeps what is code: access, ahoy models, mailers and the notifier" do
    notifier = ->(_event) { }
    config.authorize = ->(_controller) { true }
    config.visit_model = "Visit"
    config.alerts[:mailer] = "SeoAlertMailer"
    config.reports.parent_mailer = "ApplicationMailer"
    config.alert_notifier = notifier

    expect(config.visit_model).to eq("Visit")
    expect(config.alerts[:mailer]).to eq("SeoAlertMailer")
    expect(config.reports[:parent_mailer]).to eq("ApplicationMailer")
    expect(config.alert_notifier).to be(notifier)
  end

  it "defaults the mailers to the engine's own" do
    expect(config.alerts[:mailer]).to eq("AhoyDashboard::AlertMailer")
    expect(config.reports[:mailer]).to eq("AhoyDashboard::ReportMailer")
  end

  describe "cache_store" do
    it "leaves the host cache in use by default" do
      expect(config.cache_store).to be_nil
    end

    it "accepts an existing cache store" do
      store = ActiveSupport::Cache::MemoryStore.new
      config.cache_store = store

      expect(config.cache_store).to be(store)
    end

    it "accepts a Rails cache-store name" do
      config.cache_store = :null_store

      expect(config.cache_store).to be_a(ActiveSupport::Cache::NullStore)
    end

    it "resolves Rails cache-store options once" do
      config.cache_store = :memory_store, { namespace: "dashboard" }
      config.cache_store.write("example", "cached")

      expect(config.cache_store.read("example")).to eq("cached")
    end

    it "keeps the configured namespace" do
      config.cache_store = :memory_store, { namespace: "dashboard" }

      expect(config.cache_store.options[:namespace]).to eq("dashboard")
    end

    it "allows returning to the host cache" do
      config.cache_store = :memory_store
      config.cache_store = nil

      expect(config.cache_store).to be_nil
    end
  end
end
