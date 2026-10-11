require "rails_helper"

RSpec.describe AhoyDashboard::ChatMessageDecorator, type: :decorator do
  let(:chat) { AhoyDashboard::Chat.create! }

  def decorate(message)
    described_class.new(message)
  end

  def reply(**attributes)
    chat.chat_messages.create!(role: :assistant, status: :complete, **attributes)
  end

  describe "#looked_at" do
    it "names each tool once, in the words the tool gives itself" do
      message = reply(tool_calls: [ { "name" => "TrafficSummary" }, { "name" => "TrafficSummary" } ])

      expect(decorate(message).looked_at).to eq([ "the headline figures" ])
    end

    it "is empty when nothing was called" do
      expect(decorate(reply(content: "Flat.")).looked_at).to eq([])
    end
  end

  describe "#shown" do
    it "drops a view with too little in it to draw" do
      message = reply(views: [
        { "kind" => "series", "title" => "Visitors", "points" => [ [ "2026-04-01", 1 ] ] },
        { "kind" => "series", "title" => "Visits", "points" => [ [ "2026-04-01", 1 ], [ "2026-04-02", 2 ] ] }
      ])

      expect(decorate(message).shown.map(&:title)).to eq([ "Visits" ])
    end
  end

  describe "#tokens" do
    it "adds both halves up" do
      expect(decorate(reply(input_tokens: 20, output_tokens: 10)).tokens).to eq(30)
    end

    it "is nothing at all when neither was recorded" do
      expect(decorate(reply(content: "Flat.")).tokens).to be_nil
    end
  end
end
