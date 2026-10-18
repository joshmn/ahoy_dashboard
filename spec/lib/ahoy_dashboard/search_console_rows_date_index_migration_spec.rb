require "rails_helper"

RSpec.describe "Dropping the redundant Search Console rows date index" do
  let(:connection) { ActiveRecord::Base.connection }
  let(:date_index) { "index_ahoy_dashboard_search_console_rows_on_date" }
  let(:grain) { "index_ahoy_dashboard_search_console_rows_on_grain" }

  def migrate(direction = :up)
    engine_migration("search_console/remove_ahoy_dashboard_search_console_rows_date_index.rb")
    ActiveRecord::Migration.suppress_messages { RemoveAhoyDashboardSearchConsoleRowsDateIndex.new.public_send(direction) }
  end

  def indexes
    connection.indexes(:ahoy_dashboard_search_console_rows).map(&:name)
  end

  before { migrate(:down) }

  it "drops the date index and keeps the grain index that leads with date" do
    migrate

    expect(indexes).not_to include(date_index)
    expect(connection.indexes(:ahoy_dashboard_search_console_rows).find { |index| index.name == grain }.columns.first)
      .to eq("date")
  end

  it "leaves the date index alone where the grain index is missing" do
    connection.remove_index(:ahoy_dashboard_search_console_rows, name: grain)

    migrate

    expect(indexes).to include(date_index)
  end

  it "can be repeated and reversed" do
    migrate

    expect { migrate }.not_to(change { indexes })

    migrate(:down)

    expect(indexes).to include(date_index)
  end
end
