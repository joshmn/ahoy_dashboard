require "rails_helper"

RSpec.describe AhoyDashboard::PinnedQuestionsQuery do
  let(:now) { dash_time(2026, 8, 11, 14, 30) }

  around { |example| travel_to(now) { example.run } }

  def someone(at, name)
    dash_page_view(dash_visit(started_at: at, visitor: name), path: "/", at: at)
  end

  it "skips malformed stored query parameters" do
    question = create(:dash_saved_query, pinned: true, params: { "period" => "day" })
    AhoyDashboard::SavedQuery.connection.execute("UPDATE ahoy_dashboard_saved_queries SET params = '[]'::jsonb WHERE id = #{question.id}")

    expect(described_class.call(questions: [ question.reload ])).to eq([])
  end

  it "propagates a database query failure instead of silently dropping the card" do
    question = create(:dash_saved_query, pinned: true, params: { "period" => "day", "metric" => "visitors" })
    connection = AhoyDashboard.visit.connection

    connection.transaction(requires_new: true) do
      connection.execute("ALTER TABLE ahoy_visits RENAME COLUMN visitor_token TO unavailable_visitor_token")

      expect { described_class.call(questions: [ question ]) }.to raise_error(ActiveRecord::StatementInvalid)
      raise ActiveRecord::Rollback
    end
  ensure
    AhoyDashboard.visit.reset_column_information
  end

  def card(period: "day")
    question = create(:dash_saved_query, pinned: true, params: { "period" => period, "metric" => "visitors" })

    described_class.call(questions: [ question ]).first
  end

  it "holds today against yesterday by the same hour rather than the whole of it" do
    someone((now - 1.day).change(hour: 9), "morning")
    someone((now - 1.day).change(hour: 10), "before this hour")
    someone((now - 1.day).change(hour: 20), "after this hour")
    someone(now.change(hour: 9), "today one")
    someone(now.change(hour: 11), "today two")

    result = card

    expect([ result.value, result.change ]).to eq([ 2, 0 ])
  end

  def bounced(at, name)
    someone(at, name)
  end

  def browsed(at, name)
    visit = dash_landing(at: at, visitor: name)
    dash_page_view(visit, path: "/next", at: at + 1.minute)
  end

  def bounce_card
    question = create(:dash_saved_query, pinned: true, params: { "period" => "day", "metric" => "bounce_rate" })

    described_class.call(questions: [ question ]).first
  end

  it "reads the decrease in bounce rate" do
    bounced((now - 1.day).change(hour: 9), "yesterday one")
    bounced((now - 1.day).change(hour: 10), "yesterday two")
    bounced(now.change(hour: 9), "today bounced")
    browsed(now.change(hour: 10), "today browsed")

    result = bounce_card

    expect(result.change).to be_negative
  end

  it "reads the increase in bounce rate" do
    browsed((now - 1.day).change(hour: 9), "yesterday one")
    bounced((now - 1.day).change(hour: 10), "yesterday two")
    bounced(now.change(hour: 9), "today one")
    bounced(now.change(hour: 10), "today two")

    expect(bounce_card.change).to be_positive
  end

  it "counts only what the question's filters let through" do
    someone(now.change(hour: 9), "home reader")
    dash_landing("/going-in/faq", at: now.change(hour: 10), visitor: "faq reader")
    question = create(:dash_saved_query, pinned: true, params: {
      "period" => "day", "metric" => "visitors",
      "filters" => [ { "dimension" => "page", "operator" => "is", "value" => "/going-in/faq" } ]
    })

    expect(described_class.call(questions: [ question ]).first.value).to eq(1)
  end

  it "ends the sparkline at the hour that is still filling in" do
    someone(now.change(hour: 9), "one")

    expect([ card.series.size, card.series[9] ]).to eq([ 15, 1.0 ])
  end

  it "reads a finished question over the whole range before it" do
    result = card(period: "yesterday")

    expect(result.series.size).to eq(24)
  end

  describe "sharing current totals with the sparkline" do
    let(:separate_queries) do
      Class.new(described_class) do
        def self.readings
          @readings ||= []
        end

        private

        def reading_for(form)
          self.class.readings << form
          [ stat_for(form), nil ]
        end
      end
    end

    before do
      someone(now.change(hour: 9), "returning")
      someone((now - 1.day).change(hour: 9), "returning")
      someone((now - 2.days).change(hour: 9), "older")
    end

    it "preserves readings, including elapsed and last-thirty-point sparkline handling" do
      periods = [
        { "period" => "day" },
        { "period" => "yesterday" },
        { "period" => "realtime" },
        { "period" => "custom", "from" => "2026-07-01", "to" => "2026-08-11", "interval" => "day" }
      ]

      periods.product(%w[visitors visits pageviews]).each do |params, metric|
        question = create(:dash_saved_query, pinned: false, params: params.merge("metric" => metric))
        expected = separate_queries.call(questions: [ question ])

        expect(described_class.call(questions: [ question ])).to eq(expected)
      end
      expect(separate_queries.readings.size).to eq(periods.size * 3)
    end

    it "reads the current count and sparkline together plus one comparison count" do
      question = create(:dash_saved_query, pinned: true, params: { "period" => "day", "metric" => "visitors" })
      statements = captured_sql(/\bFROM\s+"?ahoy_visits\b/i, uncached: true) { described_class.call(questions: [ question ]) }

      expect([ statements.size, statements.count { |sql| sql.include?("grouping sets") } ]).to eq([ 2, 1 ])
    end
  end
end
