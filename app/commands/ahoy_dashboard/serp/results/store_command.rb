module AhoyDashboard
  module Serp
    module Results
      class StoreCommand < AhoyDashboard::Command
        COLUMNS = %w[run_id position page link domain title checked_at].freeze

        def initialize(run:, result: nil)
          @run = run
          @result = result
        end

        def call
          combined = result || run.result
          return broadcast(:nothing, run) if combined.nil?

          rows = write(combined)
          broadcast(:ok, rows)
        end

        private

        attr_reader :run, :result

        def write(combined)
          rows = combined.organic.map do |entry|
            SerpResult.new(run: run, position: entry.position, page: entry.page, link: entry.link,
                           domain: entry.domain, title: entry.title, checked_at: run.checked_at)
          end
          rows.each(&:validate!)

          run.results.delete_all(:delete_all)
          insert(rows)
          run.results.reset

          rows
        end

        def insert(rows)
          return if rows.empty?

          now = Time.current
          SerpResult.insert_all!(rows.map { |row| row.attributes.slice(*COLUMNS).merge("created_at" => now, "updated_at" => now) })
        end
      end
    end
  end
end
