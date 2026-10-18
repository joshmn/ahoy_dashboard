require "rails_helper"

RSpec.describe AhoyDashboard::ChatDecorator, type: :decorator do
  describe "#title_or_default" do
    it "uses the saved title when there is one" do
      chat = create(:dash_chat, title: "Traffic last week")

      expect(decorate(chat).title_or_default).to eq("Traffic last week")
    end

    it "falls back to the first thing that was asked" do
      chat = create(:dash_chat)
      create(:dash_chat_message, chat: chat, content: "  how is   traffic? ")

      expect(decorate(chat).title_or_default).to eq("how is traffic?")
    end

    it "says New question when nothing has been asked yet" do
      expect(decorate(create(:dash_chat)).title_or_default).to eq("New question")
    end
  end

  describe "#about_a_page?" do
    it "is true once a path was carried in from the screen it was asked on" do
      chat = create(:dash_chat, context: { "path" => "/telemetry/rankings" })

      expect(decorate(chat)).to be_about_a_page
    end

    it "is false with no context at all" do
      expect(decorate(create(:dash_chat))).not_to be_about_a_page
    end
  end
end
