module AhoyDashboard
  module SearchConsole
    ComparedWindow = Data.define(:current, :previous) do
      class << self
        def within(requested:, covered:)
          return new(current: nil, previous: nil) if covered.nil?

          first = [ requested.begin.to_date, covered.begin ].max
          last = [ requested.end.to_date, covered.end ].min
          return new(current: nil, previous: nil) if first > last

          length = (last - first).to_i + 1
          before = (first - length)..(first - 1)

          new(current: first..last, previous: (before if before.begin >= covered.begin))
        end
      end
    end
  end
end
