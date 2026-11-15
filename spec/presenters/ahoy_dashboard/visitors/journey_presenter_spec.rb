require "rails_helper"

RSpec.describe AhoyDashboard::Visitors::JourneyPresenter do
  let(:query) { AhoyDashboard::QueryForm.from_params({}) }

  def presenter_for(person, **options)
    result = AhoyDashboard::Visitors::JourneyQuery.call(person: person, **options)
    described_class.new(query: query, result: result, routes: AhoyDashboard.routes)
  end

  def user(id)
    AhoyDashboard::Visitors::PersonQuery.call(user_id: id)
  end

  describe "user labels" do
    around do |example|
      previous = AhoyDashboard::ValueLabels.registry["user_id"]
      example.run
    ensure
      previous ? AhoyDashboard::ValueLabels.registry["user_id"] = previous : AhoyDashboard::ValueLabels.registry.delete("user_id")
    end

    before { dash_landing("/", at: dash_time(2026, 8, 10, 9), visitor: "a", user_id: 7) }

    it "asks the host once for every user id on the page" do
      asked = []
      AhoyDashboard::ValueLabels.register("user_id") do |ids|
        asked << ids
        ids.map { |id| [ id, "user#{id}@example.com" ] }
      end
      presenter = presenter_for(user("7"))

      expect(presenter.title).to eq("user7@example.com")
      expect(presenter.user_label(7)).to eq("user7@example.com")
      expect(asked).to eq([ [ "7" ] ])
    end

    it "falls back to the raw id without a hook" do
      AhoyDashboard::ValueLabels.registry.delete("user_id")

      expect(presenter_for(user("7")).title).to eq("User 7")
    end
  end

  describe "links" do
    it "jumps to the identified event on the page it's on" do
      visits = Array.new(3) { |index| dash_landing("/", at: dash_time(2026, 8, 10, 9 + index), visitor: "a") }
      signed = create(:ahoy_event, visit: visits.last, name: "Signed in", time: dash_time(2026, 8, 10, 11, 5),
                                   user_id: 7, properties: {})
      visits.last.update!(user_id: 7)

      presenter = presenter_for(user("7"), per_page: 2)

      expect(presenter.identified_path).to eq("/telemetry/visitors/users/7?page=2#event-#{signed.id}")
    end
  end

  describe ".duration" do
    it "keeps the two biggest units and drops a zero second one" do
      expect(described_class.duration(0)).to eq("0s")
      expect(described_class.duration(42)).to eq("42s")
      expect(described_class.duration(125)).to eq("2m 5s")
      expect(described_class.duration(3_600)).to eq("1h")
      expect(described_class.duration(93_784)).to eq("1d 2h")
    end
  end
end
