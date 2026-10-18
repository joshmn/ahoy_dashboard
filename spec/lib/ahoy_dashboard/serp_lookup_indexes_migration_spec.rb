require "rails_helper"

RSpec.describe "Adding the rank tracking lookup indexes" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:folded) { "index_ahoy_dashboard_serp_keywords_on_folded_search" }
  let(:checked) { "index_ahoy_dashboard_serp_runs_on_checked_at" }

  def migrate(direction = :up)
    engine_migration("serp/add_ahoy_dashboard_serp_lookup_indexes.rb")
    ActiveRecord::Migration.suppress_messages { AddAhoyDashboardSerpLookupIndexes.new.public_send(direction) }
  end

  def indexes
    connection.indexes(:ahoy_dashboard_serp_keywords).map(&:name) + connection.indexes(:ahoy_dashboard_serp_runs).map(&:name)
  end

  before { migrate(:down) }

  it "adds a case-insensitive search index and a checked_at index on runs" do
    migrate

    expect(indexes).to include(folded, checked)
    expect(connection.indexes(:ahoy_dashboard_serp_keywords).find { |index| index.name == folded })
      .to have_attributes(unique: true)
  end

  it "refuses to run while two keywords differ only by capitals, naming both and deleting neither" do
    first = create(:dash_serp_keyword, query: "Best CRM")
    second = create(:dash_serp_keyword, query: "best crm")

    expect { migrate }.to raise_error(ActiveRecord::MigrationError, /differ only by capitals.*#{first.id},#{second.id}/)
    expect(indexes).not_to include(folded)
    expect(AhoyDashboard::SerpKeyword.count).to eq(2)
  end

  it "can be repeated after a successful run" do
    migrate

    expect { migrate }.not_to(change { indexes })
  end

  it "takes both indexes away on the way down" do
    migrate
    migrate(:down)

    expect(indexes).not_to include(folded, checked)
  end
end
