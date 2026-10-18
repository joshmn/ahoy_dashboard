require "rails_helper"

RSpec.describe AhoyDashboard::Decorator, type: :decorator do
  it "keeps building urls off the record rather than off itself, for every decorator" do
    entry = { "dimension" => "asn", "operator" => "contains", "value" => "AMAZON" }
    by_id = {
      AhoyDashboard::AlertRuleDecorator => create(:dash_alert_rule),
      AhoyDashboard::AnnotationDecorator => create(:dash_annotation, label: "Shipped", kind: "deploy"),
      AhoyDashboard::ChatDecorator => create(:dash_chat),
      AhoyDashboard::ExclusionDecorator => AhoyDashboard::Exclusion.create!(name: "Data centers", filters: [ entry ]),
      AhoyDashboard::GoalDecorator => create(:dash_goal),
      AhoyDashboard::SegmentDecorator => create(:dash_segment),
      AhoyDashboard::SerpKeywordDecorator => create(:dash_serp_keyword)
    }

    by_id.each do |decorator, record|
      expect(decorator.new(record).to_param).to eq(record.id.to_s), decorator.name
    end
    expect(AhoyDashboard::PropertyDecorator.new(create(:dash_property, key: "facility_id")).to_param).to eq("facility_id")
    expect(AhoyDashboard::PlaceDecorator.new(create(:dash_place, name: "United States", code: 2840)).to_param).to eq("2840")
  end

  it "hands form and render helpers the record itself" do
    goal = create(:dash_goal)

    expect(decorate(goal).to_model).to be(goal)
    expect(decorate(goal).to_partial_path).to eq(goal.to_partial_path)
  end

  it "wraps each record of a collection, in order" do
    goals = create_list(:dash_goal, 2)

    wrapped = described_class.wrap(goals)

    expect(wrapped).to all(be_an_instance_of(described_class))
    expect(wrapped.map(&:object)).to eq(goals)
  end
end
