require "rails_helper"

RSpec.describe AhoyDashboard::DigestRecord do
  def digest(model, **attributes)
    model.create!(period: :weekly, starts_on: Date.new(2026, 9, 7), ends_on: Date.new(2026, 9, 13), **attributes)
  end

  [ AhoyDashboard::AlertDigest, AhoyDashboard::ReportDigest ].each do |model|
    describe model.name do
      it "hands back the window it covers" do
        expect(digest(model).window).to eq(
          AhoyDashboard::Digests::Window.new(period: :weekly, starts_on: Date.new(2026, 9, 7), ends_on: Date.new(2026, 9, 13))
        )
      end

      it "can be claimed while pending or after a failed send" do
        expect([ digest(model), digest(model, starts_on: Date.new(2026, 9, 14), status: :failed) ].map(&:claimable?))
          .to eq([ true, true ])
      end

      it "cannot be claimed once it is sent" do
        expect(digest(model, status: :sent)).not_to be_claimable
      end

      it "cannot be claimed while another worker is sending it" do
        expect(digest(model, status: :sending)).not_to be_claimable
      end

      it "can be claimed again once a send has been stuck past the timeout" do
        stuck = digest(model, status: :sending)
        stuck.update_columns(updated_at: (described_class::CLAIM_TIMEOUT + 1.minute).ago)

        expect(stuck).to be_claimable
      end

      it "needs both ends of the window and a period it knows" do
        record = model.new(period: "hourly", starts_on: Date.new(2026, 9, 7))

        expect(record).not_to be_valid
        expect([ record.errors[:period], record.errors[:ends_on] ]).to all(be_present)
      end
    end
  end

  it "counts a skipped alert email as done, so it is not claimed again" do
    skipped = AhoyDashboard::AlertDigest.create!(period: :daily, starts_on: Date.new(2026, 9, 18),
                                                 ends_on: Date.new(2026, 9, 18), status: :skipped)

    expect([ skipped.done?, skipped.claimable? ]).to eq([ true, false ])
  end
end
