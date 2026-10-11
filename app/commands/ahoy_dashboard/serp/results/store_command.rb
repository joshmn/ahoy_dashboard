module AhoyDashboard
  module Serp
    module Results
      class StoreCommand < AhoyDashboard::Command
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
          run.results.destroy_all

          combined.organic.map do |entry|
            run.results.create!(position: entry.position, page: entry.page, link: entry.link,
                                domain: entry.domain, title: entry.title, checked_at: run.checked_at)
          end
        end
      end
    end
  end
end
