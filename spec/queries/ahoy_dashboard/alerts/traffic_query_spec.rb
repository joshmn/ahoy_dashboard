require "rails_helper"

RSpec.describe AhoyDashboard::Alerts::TrafficQuery do
  [ [ 2026, 9, 19 ], [ 2026, 11, 6 ] ].each do |year, month, day|
    it "preserves exclusive ends and distinct visitors across weekly windows on #{year}-#{month}-#{day}" do
      now = dash_time(year, month, day, 14, 30)
      finish = now.beginning_of_hour
      dash_page_view(dash_visit(started_at: now - 40.days))
      (0..4).each do |week|
        ending = finish - week.weeks
        dash_page_view(dash_visit(started_at: ending - 12.hours, visitor: "window-start"))
        dash_page_view(dash_visit(started_at: ending - 1.hour, visitor: "returning"))
        dash_page_view(dash_visit(started_at: ending - 30.minutes, visitor: "returning"))
        dash_page_view(dash_visit(started_at: ending, visitor: "excluded-end"))
        dash_page_view(dash_visit(started_at: ending - 13.hours, visitor: "excluded-gap"))
        dash_page_view(dash_visit(started_at: ending - 10.minutes), crawler: "GPTBot")
      end

      result = described_class.call(now: now)

      expect(result.hour).to have_attributes(visitors: 1, usual: 1.0)
      expect(result.half_day).to have_attributes(visitors: 2, usual: 2.0)
    end
  end
end
