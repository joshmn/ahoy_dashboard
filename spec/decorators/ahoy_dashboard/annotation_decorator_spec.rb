require "rails_helper"
require "support/ahoy_dashboard/fixtures"

RSpec.describe AhoyDashboard::AnnotationDecorator, type: :decorator do
  def decorate(annotation)
    described_class.new(annotation)
  end

  describe "#kind_label" do
    it "names the kind the way the operator picked it" do
      note = AhoyDashboard::Annotation.create!(label: "Shipped", kind: "deploy", happened_at: Time.current)

      expect(decorate(note).kind_label).to eq("Deploy")
    end

    it "falls back to the default kind" do
      note = AhoyDashboard::Annotation.create!(label: "Something", kind: "nonsense", happened_at: Time.current)

      expect(decorate(note).kind_label).to eq("Note")
    end
  end

  it "keeps building urls off the record rather than off itself" do
    note = AhoyDashboard::Annotation.create!(label: "Shipped", kind: "deploy", happened_at: Time.current)

    expect(decorate(note).to_param).to eq(note.id.to_s)
  end
end
