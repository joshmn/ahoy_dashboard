module AhoyDashboardCaching
  CARD_PARTIAL = %r{/(reports|funnels)/_card\.html\.erb\z}

  def with_cache_store(store)
    previous = Rails.cache
    Rails.cache = store
    yield
  ensure
    Rails.cache = previous
  end

  def precompute_dashboard!
    AhoyDashboard::Preferences.write(:site, precomputed_dashboard: true)
  end

  def default_snapshot_key
    query = AhoyDashboard::QueryForm.from_params({ period: "30d", filters: "none" })
    AhoyDashboard::Dashboards::SnapshotKeyQuery.call(query: query)
  end

  def rendered_card_partials(pattern = CARD_PARTIAL)
    rendered = []
    subscriber = lambda do |*, payload|
      identifier = payload[:identifier].to_s
      rendered << identifier if identifier.match?(pattern)
    end
    ActiveSupport::Notifications.subscribed(subscriber, "render_partial.action_view") { yield }
    rendered
  end
end

RSpec.configure { |config| config.include AhoyDashboardCaching }

RSpec.shared_context "with a memory cache" do
  around do |example|
    with_cache_store(ActiveSupport::Cache::MemoryStore.new) { example.run }
  ensure
    AhoyDashboard::Current.reset
  end
end

RSpec.shared_context "with fragment caching" do
  around do |example|
    fragments = AhoyDashboard::BaseController.cache_store
    caching = AhoyDashboard::BaseController.perform_caching
    with_cache_store(ActiveSupport::Cache::MemoryStore.new) do
      AhoyDashboard::BaseController.cache_store = Rails.cache
      AhoyDashboard::BaseController.perform_caching = true
      example.run
    end
  ensure
    AhoyDashboard::BaseController.cache_store = fragments
    AhoyDashboard::BaseController.perform_caching = caching
    AhoyDashboard::Current.reset
  end
end

RSpec.shared_context "with a test snapshot queue" do
  include_context "with a memory cache"

  around do |example|
    adapter = AhoyDashboard::Dashboards::SnapshotRefreshJob.queue_adapter
    AhoyDashboard::Dashboards::SnapshotRefreshJob.queue_adapter = :test
    example.run
  ensure
    AhoyDashboard::Dashboards::SnapshotRefreshJob.queue_adapter = adapter
  end
end
