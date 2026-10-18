require "rails_helper"

RSpec.describe AhoyDashboard::SearchConsoleRow do
  let(:row) do
    {
      date: Date.new(2026, 8, 10), query: "fci thomson lockdown",
      page: "https://federalprisondude.com/x",
      clicks: 4, impressions: 120, ctr: 0.0333, position: 12.4
    }
  end

  describe ".absorb" do
    it "writes nothing and counts nothing for an empty batch" do
      expect(described_class.absorb([])).to eq(0)
      expect(described_class.absorb(nil)).to eq(0)
      expect(described_class.count).to eq(0)
    end

    it "inserts a batch" do
      expect(described_class.absorb([ row ])).to eq(1)
      expect(described_class.count).to eq(1)
    end

    it "rewrites a row it has already seen instead of duplicating it" do
      described_class.absorb([ row ])
      described_class.absorb([ row.merge(clicks: 9, impressions: 200) ])

      expect(described_class.count).to eq(1)
      expect(described_class.first.clicks).to eq(9)
      expect(described_class.first.impressions).to eq(200)
    end

    it "treats the same query on a different page as a different row" do
      described_class.absorb([ row, row.merge(page: "https://federalprisondude.com/y") ])

      expect(described_class.count).to eq(2)
    end

    describe "a row whose key is too long for the index" do
      let(:huge) { row.merge(query: SecureRandom.alphanumeric(2_800)) }

      it "drops it instead of taking the batch down" do
        expect { described_class.absorb([ huge ]) }.not_to raise_error
        expect(described_class.count).to eq(0)
      end

      it "still writes every other row in the same batch" do
        expect(described_class.absorb([ huge, row ])).to eq(1)
        expect(described_class.pluck(:query)).to eq([ "fci thomson lockdown" ])
      end

      it "says so in the log rather than dropping it quietly" do
        allow(Rails.logger).to receive(:warn)

        described_class.absorb([ huge ])

        expect(Rails.logger).to have_received(:warn).with(/search console row dropped/)
      end

      it "names both halves of the key and their size in the log" do
        allow(Rails.logger).to receive(:warn)

        described_class.absorb([ huge ])

        expect(Rails.logger).to have_received(:warn).with(
          "search console row dropped for 2026-08-10, query and page are " \
          "#{huge[:query].bytesize + huge[:page].bytesize} bytes and the index holds 2500: #{huge[:query].truncate(60)}"
        )
      end

      it "keeps a long key that the index can still hold" do
        fits = row.merge(query: SecureRandom.alphanumeric(described_class::KEY_BUDGET - row[:page].bytesize))

        expect(described_class.absorb([ fits ])).to eq(1)
        expect(described_class.count).to eq(1)
      end
    end
  end

  describe "scopes" do
    before do
      described_class.absorb([
        row.merge(date: Date.new(2026, 8, 1), clicks: 1),
        row.merge(date: Date.new(2026, 8, 10), clicks: 50),
        row.merge(date: Date.new(2026, 8, 20), clicks: 5)
      ])
    end

    it "windows by date" do
      range = Date.new(2026, 8, 5).beginning_of_day..Date.new(2026, 8, 15).end_of_day

      expect(described_class.in_range(range).pluck(:clicks)).to eq([ 50 ])
    end
  end
end
