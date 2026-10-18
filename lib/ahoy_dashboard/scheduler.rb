# frozen_string_literal: true

module AhoyDashboard
  class Scheduler
    INTERVAL = 60
    SHUTDOWN_TIMEOUT = 5

    def initialize
      @mutex = Mutex.new
      reset
    end

    def start
      mutex.synchronize do
        reset if pid != Process.pid
        return self if thread && thread.alive?

        @stopping = false
        @thread = Thread.new { run }
        register_shutdown
      end
      self
    end

    def stop
      return self if pid != Process.pid

      current = mutex.synchronize do
        @stopping = true
        condition.broadcast
        thread
      end
      current.join(SHUTDOWN_TIMEOUT) if current && current != Thread.current
      self
    end

    def running?
      pid == Process.pid && mutex.synchronize { !!(thread && thread.alive?) }
    end

    private

    attr_reader :pid, :mutex, :condition, :thread, :stopping, :shutdown_registered

    def reset
      @pid = Process.pid
      @condition = ConditionVariable.new
      @thread = nil
      @stopping = true
    end

    def register_shutdown
      return if shutdown_registered

      at_exit { stop }
      @shutdown_registered = true
    end

    def run
      Thread.current.name = "ahoy_dashboard_scheduler"
      loop do
        mutex.synchronize { return if stopping }
        tick
        mutex.synchronize do
          return if stopping

          condition.wait(mutex, INTERVAL)
        end
      end
    end

    def tick
      Rails.application.reloader.wrap { AhoyDashboard::TickJob.perform_now }
    rescue StandardError => error
      Rails.logger.error("ahoy_dashboard scheduler tick failed: #{error.class}: #{error.message}")
    end
  end
end
