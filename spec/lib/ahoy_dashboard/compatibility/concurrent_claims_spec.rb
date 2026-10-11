# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Concurrent dashboard database claims" do
  self.use_transactional_tests = false

  before do
    @key = "compatibility_#{SecureRandom.hex(8)}"
    @run_ids = AhoyDashboard::AiVisibility::Run.pluck(:id)
    @cap = AhoyDashboard::Setting.find_by(key: AhoyDashboard::AiVisibility::CAP_KEY)
  end

  after do
    runs = AhoyDashboard::AiVisibility::Run.where.not(id: @run_ids)
    AhoyDashboard::AiVisibility::Answer.where(run_id: runs.select(:id)).delete_all
    runs.delete_all
    AhoyDashboard::AiVisibility::Prompt.where(id: @prompt.id).delete_all if @prompt
    AhoyDashboard::JobRun.where(key: @key).delete_all
    AhoyDashboard::SerpSpendDay.where(provider: @key).delete_all
    if @cap
      AhoyDashboard::Setting.write(AhoyDashboard::AiVisibility::CAP_KEY, @cap.value)
    else
      AhoyDashboard::Setting.where(key: AhoyDashboard::AiVisibility::CAP_KEY).delete_all
    end
  end

  def concurrently(count: 2)
    ready = Queue.new
    start = Queue.new
    threads = Array.new(count) do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          ready << connection.raw_connection.backend_pid
          start.pop
          yield(index)
        end
      end
    end
    @connection_ids = Array.new(count) { ready.pop }
    count.times { start << true }
    threads.map(&:value)
  ensure
    threads.each(&:join) if threads
  end

  it "reserves the final available AI request for only one simultaneous run" do
    AhoyDashboard::Setting.write(AhoyDashboard::AiVisibility::CAP_KEY, 1)
    @prompt = create(:dash_ai_prompt)
    target = AhoyDashboard::AiVisibility::Target.new(assistant: "openai", model: "gpt-5")
    now = Time.current

    runs = concurrently do
      AhoyDashboard::AiVisibility::Runs::ReservationService.call(
        prompts: [@prompt], targets: [target], trigger: "manual", now: now
      )
    end

    expect([runs.map(&:status).sort, @connection_ids.uniq.length]).to eq([%w[queued skipped], 2])
  end

  it "lets only one connection claim the same external AI request" do
    @prompt = create(:dash_ai_prompt)
    run = create(:dash_ai_run)
    create(:dash_ai_answer, run: run, prompt: @prompt, status: :pending)
    now = Time.current

    claims = concurrently do
      AhoyDashboard::AiVisibility::Answers::ClaimService.call(
        run: run, prompt: @prompt, assistant: "openai", model: "gpt-4.1", now: now
      )
    end

    expect([claims.compact.length, @connection_ids.uniq.length]).to eq([1, 2])
  end

  it "grants only one scheduler lease to simultaneous first-time claimants" do
    now = Time.current

    claims = concurrently do |index|
      AhoyDashboard::Scheduling::ClaimService.call(key: @key, token: "worker_#{index}", now: now)
    end

    expect([claims.count { |claim| claim }, @connection_ids.uniq.length]).to eq([1, 2])
  end

  it "adds every concurrent upsert increment atomically" do
    model = AhoyDashboard::SerpSpendDay
    date = Date.current

    concurrently(count: 4) do
      AhoyDashboard::Compatibility::Upsert.new(
        model: model, rows: [{ provider: @key, on: date, kind: :checks, units: 1 }],
        unique_by: [:provider, :on, :kind],
        on_duplicate: Arel.sql("units = #{model.quoted_table_name}.units + excluded.units")
      ).call
    end

    expect([model.find_by!(provider: @key).units, @connection_ids.uniq.length]).to eq([4, 4])
  end
end
