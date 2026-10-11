# frozen_string_literal: true

require "spec_helper"
require "ahoy_dashboard/value"

RSpec.describe AhoyDashboard::Value do
  let(:type) { described_class.define(:name, :count) }
  let(:value) { type.new(name: "visits", count: 2) }

  it "constructs values with keywords" do
    expect(value.to_h).to eq(name: "visits", count: 2)
  end

  it "constructs values positionally" do
    expect(type.new("visits", 2)).to eq(value)
  end

  it "preserves a final positional hash" do
    record = described_class.define(:name, :display, :delta)

    expect(record.new("visits", "2", { change: 1 }).delta).to eq(change: 1)
  end

  it "preserves an empty final positional hash" do
    record = described_class.define(:name, :display, :delta)

    expect(record.new("visits", "2", {}).delta).to eq({})
  end

  it "preserves string keys in a final positional hash" do
    expect(type.new("visits", { "total" => 2 }).count).to eq("total" => 2)
  end

  it "preserves multiple positional hash members" do
    expect(type.new({ first: 1 }, { second: 2 }).to_h).to eq(name: { first: 1 }, count: { second: 2 })
  end

  it "preserves an empty hash as a single positional member" do
    record = described_class.define(:payload)

    expect(record.new({}).payload).to eq({})
  end

  it "preserves a hash payload as a single positional member" do
    record = described_class.define(:payload)

    expect(record.new({ total: 2 }).payload).to eq(total: 2)
  end

  it "constructs a hash member through keywords" do
    record = described_class.define(:payload)

    expect(record.new(payload: {}).payload).to eq({})
  end

  it "rejects an incomplete positional member list" do
    expect { type.new("visits") }.to raise_error(ArgumentError)
  end

  it "allows a defaulted hash member without arguments" do
    record = described_class.define(:payload) do
      def initialize(payload: {})
        super(payload: payload)
      end
    end

    expect(record.new.payload).to eq({})
  end

  it "freezes constructed values" do
    expect(value).to be_frozen
  end

  it "requires every member" do
    expect { type.new(name: "visits") }.to raise_error(ArgumentError, /count/)
  end

  it "rejects unknown members" do
    expect { type.new(name: "visits", count: 2, extra: true) }.to raise_error(ArgumentError, /extra/)
  end

  it "returns a changed copy" do
    expect(value.with(count: 3)).to eq(type.new(name: "visits", count: 3))
  end

  it "preserves the original when copying" do
    value.with(count: 3)

    expect(value.count).to eq(2)
  end

  it "compares equal values as hash keys" do
    expect({ value => true }.fetch(type.new("visits", 2))).to eq(true)
  end

  it "keeps different record types distinct" do
    other = described_class.define(:name, :count).new("visits", 2)

    expect(value).not_to eq(other)
  end

  it "allows explicit defaults in a custom initializer" do
    custom = described_class.define(:name, :count) do
      def initialize(name:, count: 0)
        super(name: name, count: count)
      end
    end

    expect(custom.new(name: "visits").count).to eq(0)
  end

  it "supports a member named members" do
    custom = described_class.define(:members)

    expect(custom.new(members: [1]).to_h).to eq(members: [1])
  end

  it "allows behavior on the record" do
    custom = described_class.define(:count) do
      def empty?
        count.zero?
      end
    end

    expect(custom.new(0)).to be_empty
  end
end
