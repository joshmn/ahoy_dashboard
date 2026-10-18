# frozen_string_literal: true

require "rails_helper"
require "timeout"

RSpec.describe AhoyDashboard::Scheduler do
  subject(:scheduler) { described_class.new }

  let(:ticks) { Queue.new }

  before do
    stub_const("AhoyDashboard::Scheduler::INTERVAL", 0.01)
    allow(AhoyDashboard::TickJob).to receive(:perform_now) { ticks << Thread.current }
  end

  after { scheduler.stop }

  def next_tick
    Timeout.timeout(3) { ticks.pop }
  end

  it "does not start a thread when constructed" do
    expect(scheduler).not_to be_running
  end

  it "ticks repeatedly on the same background thread" do
    scheduler.start
    first = next_tick

    expect(next_tick).to be(first)
  end

  it "starts only one loop when requests arrive concurrently" do
    callers = Array.new(10) { Thread.new { scheduler.start } }
    callers.each(&:value)
    next_tick

    expect(Thread.list.count { |thread| thread.name == "ahoy_dashboard_scheduler" }).to eq(1)
  end

  it "wraps each tick in the Rails executor" do
    allow(AhoyDashboard::TickJob).to receive(:perform_now) { ticks << Rails.application.executor.active? }
    scheduler.start

    expect(next_tick).to be(true)
  end

  it "clears current attributes between ticks" do
    allow(AhoyDashboard::TickJob).to receive(:perform_now) do
      ticks << AhoyDashboard::Current.preferences
      AhoyDashboard::Current.preferences = { "previous" => true }
    end
    scheduler.start

    expect([ next_tick, next_tick ]).to eq([ nil, nil ])
  end

  it "continues ticking after an error" do
    attempts = 0
    allow(AhoyDashboard::TickJob).to receive(:perform_now) do
      attempts += 1
      raise "queue unavailable" if attempts == 1

      ticks << :recovered
    end
    scheduler.start

    expect(next_tick).to eq(:recovered)
  end

  it "logs a failed tick" do
    output = StringIO.new
    allow(Rails).to receive(:logger).and_return(Logger.new(output))
    allow(AhoyDashboard::TickJob).to receive(:perform_now) do
      ticks << :attempted
      raise "queue unavailable"
    end
    scheduler.start
    next_tick
    scheduler.stop

    expect(output.string).to include("ahoy_dashboard scheduler tick failed: RuntimeError: queue unavailable")
  end

  it "wakes the sleeping loop when stopped" do
    stub_const("AhoyDashboard::Scheduler::INTERVAL", 60)
    scheduler.start
    next_tick
    Timeout.timeout(1) { scheduler.stop }

    expect(scheduler).not_to be_running
  end

  it "can restart after being stopped" do
    stub_const("AhoyDashboard::Scheduler::INTERVAL", 60)
    scheduler.start
    first = next_tick
    scheduler.stop
    scheduler.start

    expect(next_tick).not_to be(first)
  end

  it "can stop before being started" do
    expect(scheduler.stop).to be(scheduler)
  end

  context "with database connections" do
    self.use_transactional_tests = false

    it "returns the tick's database connection to the pool before waiting" do
      stub_const("AhoyDashboard::Scheduler::INTERVAL", 60)
      allow(AhoyDashboard::TickJob).to receive(:perform_now) do
        ActiveRecord::Base.connection.select_value("SELECT 1")
      end
      allow(Rails.application.reloader).to receive(:wrap).and_wrap_original do |original, &block|
        original.call(&block)
        ticks << ActiveRecord::Base.connection_pool.active_connection?
      end
      scheduler.start

      expect(next_tick).to be_falsey
    end
  end

  context "while a tick is in flight" do
    let(:release) { Queue.new }

    before do
      allow(AhoyDashboard::TickJob).to receive(:perform_now) do
        ticks << :started
        release.pop
      end
    end

    after { release << true }

    it "limits how long shutdown waits for the tick" do
      stub_const("AhoyDashboard::Scheduler::SHUTDOWN_TIMEOUT", 0.01)
      scheduler.start
      next_tick

      expect(Timeout.timeout(1) { scheduler.stop }).to be(scheduler)
    end

    it "does not start a second loop during shutdown" do
      stub_const("AhoyDashboard::Scheduler::SHUTDOWN_TIMEOUT", 0.01)
      scheduler.start
      next_tick
      scheduler.stop
      scheduler.start

      expect(Thread.list.count { |thread| thread.name == "ahoy_dashboard_scheduler" }).to eq(1)
    end
  end
end
