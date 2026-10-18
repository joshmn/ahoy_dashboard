require "rails_helper"

RSpec.describe AhoyDashboard::AiVisibility::AnswerDecorator, type: :decorator do
  describe "#served_differently?" do
    it "is true when the answer came back from another model" do
      answer = build(:dash_ai_answer, model: "gpt-4.1", served_model: "gpt-4.1-2025-04-14")

      expect(decorate(answer)).to be_served_differently
    end

    it "is false when it is the model that was asked for" do
      answer = build(:dash_ai_answer, model: "gpt-4.1", served_model: "gpt-4.1")

      expect(decorate(answer)).not_to be_served_differently
    end

    it "is false when nothing came back saying which model answered" do
      expect(decorate(build(:dash_ai_answer, served_model: nil))).not_to be_served_differently
    end
  end
end
