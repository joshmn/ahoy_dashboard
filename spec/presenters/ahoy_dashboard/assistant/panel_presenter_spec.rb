require "rails_helper"

RSpec.describe AhoyDashboard::Assistant::PanelPresenter do
  let(:query) { AhoyDashboard::QueryForm.from_params(ActionController::Parameters.new(period: "7d")) }

  def panel(**options)
    described_class.new(page: "/telemetry/explore?period=7d", query: query, **options)
  end

  it "is about the screen behind it until it holds a conversation" do
    expect(panel.about).to eq("Explore, last 7 days")
  end

  it "is about the screen a conversation was started from once it holds one" do
    chat = create(:dash_chat, context: { "path" => "/telemetry/rankings", "screen" => "rankings" })

    expect(panel(chat: chat).about).to eq("Rankings")
  end

  it "carries the view, the screen and the conversation in its links" do
    chat = create(:dash_chat)

    expect(panel(chat: chat).params).to eq(period: "7d", page: "/telemetry/explore?period=7d", chat_id: chat.id)
  end

  it "starts over with everything but the conversation" do
    chat = create(:dash_chat)

    expect(panel(chat: chat).fresh_params).to eq(period: "7d", page: "/telemetry/explore?period=7d")
    expect(panel.params).to eq(panel.fresh_params)
  end

  it "snapshots the screen behind it for a new conversation" do
    expect(panel.context).to include("path" => "/telemetry/explore?period=7d", "window" => "Last 7 days")
  end
end
