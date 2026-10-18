# frozen_string_literal: true

require "rails_helper"
require "timeout"

RSpec.describe AhoyDashboard::Scheduler::Middleware do
  let(:scheduler) { AhoyDashboard::Scheduler.new }
  let(:ticks) { Queue.new }
  let(:response) { [ 200, { "content-type" => "text/plain" }, [ "ok" ] ] }
  let(:app) { ->(_env) { response } }
  let(:middleware) { described_class.new(app) }

  before do
    allow(AhoyDashboard).to receive(:scheduler).and_return(scheduler)
    allow(AhoyDashboard::TickJob).to receive(:perform_now) { ticks << Process.pid }
  end

  after { scheduler.stop }

  def next_tick
    Timeout.timeout(3) { ticks.pop }
  end

  def in_worker
    reader, writer = IO.pipe
    worker = fork do
      reader.close
      result = yield
      writer.write(JSON.generate(result))
      writer.close
      scheduler.stop
      Process.exit!(0)
    end
    writer.close
    result = Timeout.timeout(5) { JSON.parse(reader.read) }
    Process.wait(worker)
    worker = nil
    result
  ensure
    reader.close if reader && !reader.closed?
    writer.close if writer && !writer.closed?
    if worker
      Process.kill("KILL", worker)
      Process.wait(worker)
    end
  end

  it "does not start the scheduler while building the Rack stack" do
    middleware

    expect(scheduler).not_to be_running
  end

  it "passes the request through unchanged" do
    expect(middleware.call({})).to be(response)
  end

  it "starts the scheduler on the first request" do
    middleware.call({})

    expect(next_tick).to eq(Process.pid)
  end

  context "with forked workers" do
    before { skip("fork is unavailable") unless Process.respond_to?(:fork) }

    it "starts in the worker after preloading without starting in the master" do
      middleware
      result = in_worker do
        middleware.call({})
        [ next_tick == Process.pid, scheduler.running? ]
      end

      expect([ result, scheduler.running? ]).to eq([ [ true, true ], false ])
    end

    it "starts in a worker that builds its own Rack stack" do
      result = in_worker do
        described_class.new(app).call({})
        next_tick == Process.pid
      end

      expect(result).to be(true)
    end

    it "replaces an inherited thread when a running worker forks another worker" do
      middleware.call({})
      next_tick
      result = in_worker do
        inherited_running = scheduler.running?
        middleware.call({})
        [ inherited_running, next_tick == Process.pid ]
      end

      expect([ result, scheduler.running? ]).to eq([ [ false, true ], true ])
    end

    it "starts only one loop for simultaneous requests after a fork" do
      middleware.call({})
      next_tick
      result = in_worker do
        callers = Array.new(10) { Thread.new { middleware.call({}) } }
        callers.each(&:value)
        next_tick
        Thread.list.count { |thread| thread.name == "ahoy_dashboard_scheduler" }
      end

      expect(result).to eq(1)
    end
  end
end
