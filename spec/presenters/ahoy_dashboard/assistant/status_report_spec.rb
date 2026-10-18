require "rails_helper"

RSpec.describe AhoyDashboard::Assistant::StatusReport do
  it "runs from bin/rails ahoy_dashboard:assistant without raising" do
    expect(run_dashboard_task("ahoy_dashboard:assistant")).to match(/^enabled: /)
  end

  it "says what it is set up with, and why it is not answering" do
    lines = described_class.lines

    expect(lines).to include("enabled: false", "available: false", "reader: anthropic, the default until one is chosen on settings, assistant",
                             "temperature: the model's own", "kept out: nothing")
    expect(lines).to include(a_string_starting_with("why not: the assistant is switched off"))
    expect(lines).to include("next: switch the assistant on under settings, features")
    expect(lines).to include("tool trend: the trend over time")
  end

  it "names where the key comes from and the last error the provider sent" do
    create(:dash_assistant_provider, :active, name: "openai", model: "gpt-5-mini",
                                               credentials: { api_key: "typed-in" },
                                               last_error: "401 from the model: bad key")

    lines = described_class.lines

    expect(lines).to include("reader: openai", "model: gpt-5-mini",
                             "endpoint: https://api.openai.com/v1", "key: stored on the settings screen",
                             "last error: 401 from the model: bad key")
    expect(lines.join("\n")).not_to include("typed-in")
  end

  it "points only at the settings screen when the reader has no key" do
    switch_on_ahoy_dashboard(:assistant)
    create(:dash_assistant_provider, :active, model: "claude-opus-5")

    lines = described_class.lines

    expect(lines).to include("key: missing", "next: save a key for Anthropic on settings, assistant")
    expect(lines.join("\n")).not_to include("config.", "credentials]")
  end

  it "prints plain lines with no indentation" do
    expect(described_class.lines).to all(match(/\A[a-z]/))
  end

  it "says in one line how to install it when its tables are missing" do
    uninstall_ahoy_dashboard(:assistant)

    expect(described_class.lines).to eq([
      "the assistant is not installed. run bin/rails generate ahoy_dashboard:install " \
      "--only assistant, then bin/rails db:migrate"
    ])
  end

  it "marks a tool whose feature is not installed as not offered" do
    uninstall_ahoy_dashboard(:serp)

    expect(described_class.lines).to include(
      "tool rankings: the rank tracking, not offered because rank tracking is not installed. " \
      "run bin/rails generate ahoy_dashboard:install --only serp, then bin/rails db:migrate"
    )
    expect(described_class.lines).to include("tool search_console: Search Console")
  end
end
