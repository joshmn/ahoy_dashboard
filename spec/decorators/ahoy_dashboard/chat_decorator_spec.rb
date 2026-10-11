require "rails_helper"

RSpec.describe AhoyDashboard::ChatDecorator, type: :decorator do
  def decorate(chat)
    described_class.new(chat)
  end

  describe "#title_or_default" do
    it "uses the saved title when there is one" do
      chat = AhoyDashboard::Chat.create!(title: "Traffic last week")

      expect(decorate(chat).title_or_default).to eq("Traffic last week")
    end

    it "falls back to the first thing that was asked" do
      chat = AhoyDashboard::Chat.create!
      chat.chat_messages.create!(role: :user, status: :complete, content: "  how is   traffic? ")

      expect(decorate(chat).title_or_default).to eq("how is traffic?")
    end

    it "says New question when nothing has been asked yet" do
      expect(decorate(AhoyDashboard::Chat.create!).title_or_default).to eq("New question")
    end
  end

  describe "#about_a_page?" do
    it "is true once a path was carried in from the screen it was asked on" do
      chat = AhoyDashboard::Chat.create!(context: { "path" => "/telemetry/rankings" })

      expect(decorate(chat)).to be_about_a_page
    end

    it "is false with no context at all" do
      expect(decorate(AhoyDashboard::Chat.create!)).not_to be_about_a_page
    end
  end

  it "keeps building urls off the record rather than off itself" do
    chat = AhoyDashboard::Chat.create!

    expect(decorate(chat).to_param).to eq(chat.id.to_s)
  end
end
