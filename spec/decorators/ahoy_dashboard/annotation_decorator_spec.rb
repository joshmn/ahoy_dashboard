require "rails_helper"

RSpec.describe AhoyDashboard::AnnotationDecorator, type: :decorator do
  describe "#kind_label" do
    it "names the kind the way the operator picked it" do
      note = create(:dash_annotation, label: "Shipped", kind: "deploy")

      expect(decorate(note).kind_label).to eq("Deploy")
    end

    it "falls back to the default kind" do
      note = create(:dash_annotation, label: "Something", kind: "nonsense")

      expect(decorate(note).kind_label).to eq("Note")
    end
  end
end
