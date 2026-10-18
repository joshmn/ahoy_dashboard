# frozen_string_literal: true

require "rails_helper"

RSpec.describe AhoyDashboard::Sql::GoalCompiler do
  let(:visit) { create(:ahoy_visit) }

  def matches(goal)
    AhoyDashboard.event.where(described_class.new(goal: goal).predicate).order(:id).pluck(:id)
  end

  it "quotes event names when evaluating the predicate" do
    matched = dash_goal(visit, "it's booked")
    dash_goal(visit, "booked")
    goal = build(:dash_goal, event_name: "it's booked")

    expect(matches(goal)).to eq([matched.id])
  end

  it "treats path percent signs and underscores literally while expanding stars" do
    matched = dash_page_view(visit, path: "/a_b/100%/done")
    dash_page_view(visit, path: "/axb/100percent/done")
    goal = build(:dash_goal, :pageview, path_pattern: "/a_b/100%/*")

    expect(matches(goal)).to eq([matched.id])
  end

  it "preserves a literal backslash in a page pattern" do
    matched = dash_page_view(visit, path: "/a\\b/done")
    dash_page_view(visit, path: "/ab/done")
    goal = build(:dash_goal, :pageview, path_pattern: "/a\\b/*")

    expect(matches(goal)).to eq([matched.id])
  end

  it "quotes property keys and values without broadening the predicate" do
    matched = dash_goal(visit, "booked", "person's name" => "O'Neil")
    dash_goal(visit, "booked", "person's name" => "Other")
    goal = build(:dash_goal, event_name: "booked", property_key: "person's name", property_value: "O'Neil")

    expect(matches(goal)).to eq([matched.id])
  end

  it "uses the first matching definition in position order" do
    event = dash_page_view(visit, path: "/thanks")
    create(:dash_goal, :pageview, path_pattern: "/*", display_name: "Any page", position: 2)
    create(:dash_goal, :pageview, path_pattern: "/thanks", display_name: "Customer's thanks", position: 1)

    expect(AhoyDashboard.event.where(id: event.id).pluck(described_class.match_case)).to eq(["Customer's thanks"])
  end

  it "has no case expression when no goals are defined" do
    expect(described_class.match_case(goals: [])).to be_nil
  end

  it "names the events a set of goals can match, page views once" do
    goals = [ build(:dash_goal, event_name: "booked"), build(:dash_goal, :pageview, path_pattern: "/a"),
              build(:dash_goal, :pageview, path_pattern: "/b"), build(:dash_goal, event_name: "booked") ]

    expect(described_class.event_names(goals)).to eq([ "booked", AhoyDashboard::PAGE_VIEW ])
  end
end
