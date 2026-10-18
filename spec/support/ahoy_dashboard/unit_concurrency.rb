module DashboardConcurrency
  def run_concurrently(count: 2, pool: ActiveRecord::Base.connection_pool)
    ready = Queue.new
    start = Queue.new
    threads = Array.new(count) do |index|
      Thread.new do
        pool.with_connection do |connection|
          ready << connection.raw_connection.backend_pid
          start.pop
          yield(index, connection)
        end
      end
    end
    @concurrent_backends = Array.new(count) { ready.pop }
    count.times { start << true }
    threads.map(&:value)
  ensure
    threads.each(&:join) if threads
  end

  def concurrent_backends
    @concurrent_backends
  end
end

RSpec.configure { |config| config.include DashboardConcurrency }
