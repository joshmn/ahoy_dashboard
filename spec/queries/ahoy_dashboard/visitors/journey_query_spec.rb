require "rails_helper"

RSpec.describe AhoyDashboard::Visitors::JourneyQuery do
  def clock(day, hour, minute = 0)
    dash_time(2026, 8, day, hour, minute)
  end

  def visitor(token)
    AhoyDashboard::Visitors::PersonQuery.call(visitor_token: token)
  end

  def user(id)
    AhoyDashboard::Visitors::PersonQuery.call(user_id: id)
  end

  def journey(person, **options)
    described_class.call(person: person, **options)
  end

  describe "one visitor token" do
    it "lists that token's visits oldest first, whatever order they were recorded in" do
      later = dash_landing("/pricing", at: clock(12, 9), visitor: "a")
      earlier = dash_landing("/", at: clock(10, 9), visitor: "a")
      dash_landing("/", at: clock(11, 9), visitor: "b")

      result = journey(visitor("a"))

      expect(result.visits.map(&:id)).to eq([ earlier.id, later.id ])
      expect(result.total_visits).to eq(2)
      expect(result.first_at).to eq(earlier.started_at)
      expect(result.last_at).to eq(later.started_at)
    end

    it "orders each visit's events by time, not by when they were written" do
      visit = dash_visit(started_at: clock(10, 9), visitor: "a")
      third = dash_goal(visit, "Signed up", { plan: "pro" }, at: clock(10, 9, 20))
      first = dash_page_view(visit, path: "/", at: clock(10, 9, 1))
      second = dash_page_view(visit, path: "/signup", at: clock(10, 9, 5))

      events = journey(visitor("a")).visits.first.events

      expect(events.map(&:id)).to eq([ first.id, second.id, third.id ])
      expect(events.map(&:path)).to eq([ "/", "/signup", nil ])
      expect(events.last.properties).to eq("plan" => "pro")
    end

    it "is nothing for a token nobody has" do
      expect(visitor("missing")).to be_nil
      expect(visitor("")).to be_nil
    end
  end

  describe "a user across visitor tokens" do
    let!(:anonymous) { dash_landing("/", at: clock(10, 9), visitor: "laptop") }
    let!(:signed_in) { dash_landing("/account", at: clock(11, 9), visitor: "laptop", user_id: 7) }
    let!(:phone) { dash_landing("/deals", at: clock(12, 9), visitor: "phone", user_id: 7) }
    let!(:phone_before) { dash_landing("/", at: clock(9, 9), visitor: "phone") }
    let!(:tablet) do
      dash_visit(started_at: clock(13, 9), visitor: "tablet").tap do |visit|
        create(:ahoy_event, visit: visit, name: "Opened", time: clock(13, 9, 1), user_id: 7, properties: {})
      end
    end
    let!(:stranger) { dash_landing("/", at: clock(10, 10), visitor: "stranger", user_id: 8) }

    it "merges every visit with the user id and every visit sharing their tokens, in time order" do
      result = journey(user("7"))

      expect(result.visits.map(&:id)).to eq([ phone_before.id, anonymous.id, signed_in.id, phone.id, tablet.id ])
      expect(result.person.visitor_tokens).to contain_exactly("laptop", "phone", "tablet")
    end

    it "leaves out other users" do
      expect(journey(user("7")).visits.map(&:id)).not_to include(stranger.id)
    end

    it "marks the first visit the user id shows up on when no event carries it" do
      identified = journey(user("7")).identified

      expect(identified.visit_id).to eq(signed_in.id)
      expect(identified.event_id).to be_nil
    end

    it "marks the first event that carries the user id when it falls inside that visit" do
      signed = create(:ahoy_event, visit: signed_in, name: "Signed in", time: clock(11, 9, 3), user_id: 7, properties: {})
      create(:ahoy_event, visit: signed_in, name: "Saved", time: clock(11, 9, 8), user_id: 7, properties: {})

      identified = journey(user("7")).identified

      expect(identified.visit_id).to eq(signed_in.id)
      expect(identified.event_id).to eq(signed.id)
      expect(identified.at).to eq(signed.time)
    end

    it "says which page the identified visit lands on" do
      result = journey(user("7"), per_page: 2)

      expect(result.identified_page).to eq(2)
    end

    it "is found by visitor token too, with the user ids it carries" do
      result = journey(visitor("laptop"))

      expect(result.visits.map(&:id)).to eq([ anonymous.id, signed_in.id ])
      expect(result.user_ids).to eq([ 7 ])
      expect(result.identified.visit_id).to eq(signed_in.id)
    end

    it "is nothing for a user id nobody has, or one that can't be an id" do
      expect(user("999")).to be_nil
      expect(user("abc")).to be_nil
      expect(user("")).to be_nil
    end
  end

  describe "the cap" do
    it "pages through visits" do
      visits = Array.new(5) { |index| dash_landing("/", at: clock(10, 9 + index), visitor: "a") }

      first = journey(visitor("a"), per_page: 2)
      last = journey(visitor("a"), per_page: 2, page: 3)

      expect(first.visits.map(&:id)).to eq(visits.first(2).map(&:id))
      expect(first.pages).to eq(3)
      expect(last.visits.map(&:id)).to eq([ visits.last.id ])
    end

    it "keeps a page past the end on the last page" do
      dash_landing("/", at: clock(10, 9), visitor: "a")

      expect(journey(visitor("a"), page: 40).page).to eq(1)
    end

    it "lists the first events of a long visit and counts the rest" do
      visit = dash_visit(started_at: clock(10, 9), visitor: "a")
      events = Array.new(5) { |index| dash_page_view(visit, path: "/#{index}", at: clock(10, 9, index)) }

      shown = journey(visitor("a"), events_per_visit: 3)
      listed = shown.visits.first

      expect(listed.events.map(&:id)).to eq(events.first(3).map(&:id))
      expect(listed.event_count).to eq(5)
      expect(listed).to be_capped
      expect(shown.total_events).to eq(5)
    end
  end

  describe "hidden traffic" do
    it "leaves out excluded visits and counts them, unless they're asked for" do
      dash_landing("/", at: clock(10, 9), visitor: "a", country: "US")
      dash_landing("/", at: clock(11, 9), visitor: "a", country: "CA")
      dash_exclusion("Canada", [ "country", "is", "CA" ])

      hidden = journey(visitor("a"))
      shown = journey(visitor("a"), include_internal: true)

      expect(hidden.total_visits).to eq(1)
      expect(hidden.hidden_visits).to eq(1)
      expect(shown.total_visits).to eq(2)
      expect(shown.hidden_visits).to eq(0)
    end

    it "leaves out crawler events, and visits with nothing else, unless they're asked for" do
      human = dash_landing("/", at: clock(10, 9), visitor: "a")
      create(:page_view_event, :crawler, visit: human, time: clock(10, 9, 1))
      bot = dash_visit(started_at: clock(11, 9), visitor: "a")
      create(:page_view_event, :crawler, visit: bot, time: clock(11, 9))

      hidden = journey(visitor("a"))
      shown = journey(visitor("a"), include_crawlers: true)

      expect(hidden.visits.map(&:id)).to eq([ human.id ])
      expect(hidden.visits.first.events.size).to eq(1)
      expect(hidden.hidden_visits).to eq(1)
      expect(shown.visits.map(&:id)).to eq([ human.id, bot.id ])
      expect(shown.visits.first.events.size).to eq(2)
    end
  end

  describe "#page_of" do
    it "finds the page a visit is on, and nothing for one that's hidden" do
      visits = Array.new(3) { |index| dash_landing("/", at: clock(10, 9 + index), visitor: "a", country: "US") }
      hidden = dash_landing("/", at: clock(10, 20), visitor: "a", country: "CA")
      dash_exclusion("Canada", [ "country", "is", "CA" ])
      query = described_class.new(person: visitor("a"), per_page: 2)

      expect(query.page_of(visits.first)).to eq(1)
      expect(query.page_of(visits.last)).to eq(2)
      expect(query.page_of(hidden)).to be_nil
    end
  end
end
