require "rails_helper"

RSpec.describe AhoyDashboard::Places::SearchQuery do
  def place(name, code:, parent: nil, country: "us", kind: "city", children: 0)
    create(:dash_place, code: code, name: name, label: name.split(",").first, parent_code: parent,
                        country_code: country, kind: kind, depth: name.split(",").size - 1,
                        children_count: children)
  end

  let!(:us) { place("United States", code: 2840, kind: "country", children: 2) }
  let!(:uk) { place("United Kingdom", code: 2826, country: "gb", kind: "country", children: 1) }
  let!(:illinois) { place("Illinois,United States", code: 21147, parent: 2840, kind: "state", children: 3) }
  let!(:florida) { place("Florida,United States", code: 21149, parent: 2840, kind: "state", children: 1) }
  let!(:chicago) { place("Chicago,Illinois,United States", code: 101, parent: 21147) }
  let!(:springfield) { place("Springfield,Illinois,United States", code: 102, parent: 21147) }
  let!(:spring_bay) { place("Spring Bay Township,Illinois,United States", code: 103, parent: 21147) }
  let!(:spring_hill) { place("Spring Hill,Florida,United States", code: 104, parent: 21149) }
  let!(:england) { place("England,United Kingdom", code: 20339, parent: 2826, country: "gb", kind: "country region") }

  def names(result)
    result.places.map(&:name)
  end

  describe "with nothing named" do
    it "offers the countries" do
      expect(names(described_class.call)).to eq([ "United Kingdom", "United States" ])
    end

    # Picking a country the provider refuses would save a keyword it will not
    # run, so it is never on offer in the first place.
    it "leaves out a country the search provider cannot search from" do
      expect(names(described_class.call(countries: [ "us" ]))).to eq([ "United States" ])
    end
  end

  describe "with a parent" do
    it "lists what is directly inside it" do
      expect(names(described_class.call(parent: us))).to eq([ "Florida,United States", "Illinois,United States" ])
    end

    it "lists a state's own places" do
      expect(names(described_class.call(parent: illinois)))
        .to eq([ "Chicago,Illinois,United States", "Spring Bay Township,Illinois,United States",
                 "Springfield,Illinois,United States" ])
    end

    it "says there is more than it sent" do
      result = described_class.call(parent: illinois, limit: 2)

      expect(result.places.size).to eq(2)
      expect(result.more).to be(true)
    end

    # A country list cut off at Fiji is not a country list, and neither is a
    # state list that stops before Texas. Both are small and fixed. The level
    # under them is not, so that one is capped and typed at instead.
    it "sends every country and every state, and caps only what is under them" do
      expect(described_class::ROOT_LIMIT).to be >= 240
      expect(described_class::BRANCH_LIMIT).to be >= 377
      expect(described_class::LISTING_LIMIT).to be < described_class::BRANCH_LIMIT
    end
  end

  describe "searching" do
    it "matches the start of a place's own name" do
      expect(names(described_class.call(term: "chic"))).to eq([ "Chicago,Illinois,United States" ])
    end

    it "answers the shortest name first, so the big one is not buried" do
      expect(names(described_class.call(term: "unit"))).to eq([ "United States", "United Kingdom" ])
    end

    it "puts a state above a city that starts the same way" do
      place("Florida City,Florida,United States", code: 105, parent: 21149)

      expect(names(described_class.call(term: "florida")))
        .to eq([ "Florida,United States", "Florida City,Florida,United States" ])
    end

    # Matching the second word anywhere in the string made "spring il" find
    # Spring Hill in Florida, off the l in Hill.
    it "reads a second word as the start of somewhere further up the path" do
      expect(names(described_class.call(term: "spring il")))
        .to eq([ "Springfield,Illinois,United States", "Spring Bay Township,Illinois,United States" ])
    end

    # Somebody who has opened Illinois and typed spring means these ones.
    it "searches inside wherever the picker is standing" do
      expect(names(described_class.call(parent: illinois, term: "spring")))
        .to eq([ "Springfield,Illinois,United States", "Spring Bay Township,Illinois,United States" ])
    end

    it "does not reach into another country from inside one" do
      expect(names(described_class.call(parent: uk, term: "chic"))).to be_empty
    end

    it "treats a wildcard as a character somebody typed" do
      expect(names(described_class.call(term: "chic%"))).to be_empty
    end

    it "lists rather than searches on one letter, which would match half the world" do
      expect(names(described_class.call(term: "u"))).to eq([ "United Kingdom", "United States" ])
    end
  end
end
