require "rails_helper"

RSpec.describe AhoyDashboard::Seo::AiVisibilityPresenter do
  def presenter(prompts: 3)
    described_class.new(query: double(to_query: {}), result: double(prompts: prompts),
                        surface: AhoyDashboard::Seo::Surface.find("ai_visibility"))
  end

  before do
    allow(AhoyDashboard::AiVisibility).to receive(:enabled?).and_return(true)
  end

  it "reuses the report's prompt count and one target read across controls, setup and the model menu" do
    create(:dash_ai_assistant, :keyed, models: %w[gpt-5 gpt-4.1])
    allow(AhoyDashboard::AiVisibility).to receive(:remaining).and_return(3)
    shown = presenter
    sql = []
    subscriber = ->(_name, _started, _finished, _id, payload) { sql << payload[:sql] if payload[:sql].match?(/\ASELECT/) }

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      expect(shown.run_reason).to eq("A run needs 6 requests and 3 are left this month.")
      expect(shown.run_confirm).to include("6 paid requests")
      expect(shown.setup_notice).to be_nil
      expect(shown.assistant_options.map { |option| option[:label] }).to include("ChatGPT, gpt-4.1", "ChatGPT, gpt-5")
      expect(shown.prompts?).to be(true)
      expect(shown.requests_per_run).to eq(6)
    end

    expect(sql.grep(/ahoy_dashboard_ai_visibility_prompts/)).to be_empty
    expect(sql.grep(/ahoy_dashboard_ai_visibility_assistants/).size).to eq(1)
  end

  it "reads changed assistant configuration in a new presenter and preserves empty prompt setup" do
    assistant = create(:dash_ai_assistant, :keyed)
    expect(presenter.asked?).to be(true)
    expect(presenter(prompts: 0).setup_notice[:title]).to eq("Write your prompts to get started")

    assistant.update!(enabled: false)

    expect(presenter.asked?).to be(false)
    expect(presenter.setup_notice[:title]).to eq("Turn on an assistant to get started")
  end
end
