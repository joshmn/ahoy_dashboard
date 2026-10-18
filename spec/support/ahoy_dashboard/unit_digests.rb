RSpec.shared_examples "a digest job" do |mailer:, run_key:, subjects:|
  let(:deliveries) { ActionMailer::Base.deliveries }

  def run_at(time)
    travel_to(AhoyDashboard.time_zone.parse(time)) { described_class.perform_now }
  end

  it "sends all three the morning a month starts on a Monday" do
    run_at("2026-06-01 07:05")

    expect(deliveries.map(&:subject)).to contain_exactly(
      a_string_starting_with(subjects.fetch(:daily)),
      a_string_starting_with(subjects.fetch(:weekly)),
      a_string_starting_with(subjects.fetch(:monthly))
    )
  end

  it "sends only the daily one the day after" do
    run_at("2026-06-01 07:05")
    deliveries.clear

    run_at("2026-06-02 07:05")

    expect(deliveries.map(&:subject)).to contain_exactly(a_string_starting_with(subjects.fetch(:next_day)))
  end

  it "sends nothing twice when it runs again the same day" do
    run_at("2026-06-01 07:05")
    run_at("2026-06-01 11:00")

    expect(deliveries.size).to eq(3)
  end

  it "fails the run when a send fails, so the jobs screen shows it" do
    allow(mailer).to receive(:with).and_raise(RuntimeError, "smtp is down")

    expect { run_at("2026-06-02 07:05") }
      .to raise_error(described_class::DeliveryError, /daily: RuntimeError: smtp is down/)
    expect(AhoyDashboard::JobRun.find_by(key: run_key)).to have_attributes(status: "failed")
  end
end

RSpec.shared_examples "a digest send command" do |scope:, mailer:, record:, day:|
  it "sends a period once however often it is asked" do
    send_digest

    expect(send_digest).to include(:already_done)
    expect(deliveries.size).to eq(1)
  end

  it "leaves a period alone while another worker is sending it" do
    record.create!(period: :daily, starts_on: day, ends_on: day, status: :sending)

    expect(send_digest).to include(:busy)
    expect(deliveries).to be_empty
  end

  it "records a failed send and tries it again on the next run" do
    allow(mailer).to receive(:with).and_raise(RuntimeError, "smtp is down")

    expect(send_digest[:failed].last.message).to eq("smtp is down")
    expect(digest).to have_attributes(status: "failed", error: "RuntimeError: smtp is down")

    allow(mailer).to receive(:with).and_call_original

    expect { send_digest }.to change(deliveries, :size).by(1)
    expect(digest).to have_attributes(status: "sent", error: nil)
  end

  it "does nothing when nobody is set to get it" do
    with_ahoy_dashboard_settings(scope, recipients: []) do
      expect(send_digest).to include(:disabled)
    end

    expect(record.count).to eq(0)
  end
end
