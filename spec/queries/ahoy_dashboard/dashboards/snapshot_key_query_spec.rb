# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::Dashboards::SnapshotKeyQuery do
  around { |example| travel_to(Time.utc(2026, 8, 11, 14, 30)) { example.run } }

  def key
    described_class.call(query: AhoyDashboard::QueryForm.from_params({period: "30d", filters: "none"}))
  end

  it "keeps traffic changes out of the definition identity" do
    original = key
    dash_page_view(dash_visit(started_at: Time.current))

    expect(key).to eq(original)
  end

  it "changes after a goal predicate changes" do
    goal = create(:dash_goal)
    original = key
    goal.update_column(:event_name, "new_conversion")

    expect(key).not_to eq(original)
  end

  it "detects a reorder that does not update timestamps" do
    question = create(:dash_saved_query, pinned: true)
    original = key
    question.update_column(:position, question.position + 1)

    expect(key).not_to eq(original)
  end

  it "detects a deleted annotation" do
    annotation = create(:dash_annotation)
    original = key
    annotation.delete

    expect(key).not_to eq(original)
  end

  it "changes when the Search Console property changes" do
    account = create(:dash_google_account, :with_property)
    original = key
    account.update_column(:property_uri, "sc-domain:other.example")

    expect(key).not_to eq(original)
  end

  it "changes at the dashboard calendar boundary" do
    original = key
    travel(1.day)

    expect(key).not_to eq(original)
  end

  it "includes the active PostgreSQL search path" do
    connection = AhoyDashboard::Record.connection
    original_path = connection.schema_search_path
    original = key
    connection.schema_search_path = "public, pg_catalog"

    expect(key).not_to eq(original)
  ensure
    connection.schema_search_path = original_path
  end

  it "includes resolved registered SQL rather than callable object identity" do
    expression = "ahoy_visits.country"
    AhoyDashboard::Dimension.register(key: "snapshot_country", label: "Country", group: "Location",
      scope: :visit, sql: -> { expression })
    original = key
    expression = "ahoy_visits.city"

    expect(key).not_to eq(original)
  end

  it "keeps equivalent registered callables stable across process object identities" do
    options = {key: "snapshot_country", label: "Country", group: "Location", scope: :visit}
    AhoyDashboard::Dimension.register(**options, sql: -> { "ahoy_visits.country" })
    original = key
    AhoyDashboard::Dimension.register(**options, sql: -> { "ahoy_visits.country" })

    expect(key).to eq(original)
  end

  it "isolates engine definition scopes even when both tenants have no matching records" do
    model = AhoyDashboard::Annotation
    previous_scopes = model.default_scopes.dup
    tenant = "First tenant"
    model.class_eval { default_scope -> { where(label: tenant) } }
    first = [model.count, key]
    tenant = "Second tenant"
    second = [model.count, key]

    expect([first.first, second.first, first.last == second.last]).to eq([0, 0, false])
  ensure
    model.default_scopes = previous_scopes
  end
end
