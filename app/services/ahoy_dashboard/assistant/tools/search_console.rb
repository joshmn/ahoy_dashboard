module AhoyDashboard
  module Assistant
    module Tools
      class SearchConsole < BaseTool
        DEFAULT_LIMIT = 10
        NO_IMPRESSIONS = "None".freeze
        NO_POSITION = "position is null on a day with no impressions, because there was nothing to average. " \
                      "it is not a top spot. a day with recorded false was never pulled from google, so its " \
                      "counts are unknown rather than zero.".freeze

        label "Search Console"

        def self.feature
          :search_console
        end

        desc "Call this for what people searched on Google before they came: queries, clicks, impressions " \
             "and average position from Google Search Console, or one query's day by day history. Position " \
             "here is an impression weighted average, not a rank. For where the site actually placed on a " \
             "results page, call rankings instead."

        params do
          string :query, description: "One search term to read the day by day history of. Leave it out for the top queries.",
                         required: false
          integer :limit, description: "How many queries, from 1 to 50. Defaults to 10.", required: false
          AhoyDashboard::Assistant::Tools::BaseTool.window_params(self)
        end

        def execute(query: nil, limit: DEFAULT_LIMIT, **asked)
          return { error: "search console is not installed, so there is nothing to read" } unless self.class.available?

          read = window(**asked)

          query.present? ? keyword(read, query) : top(read, limit)
        rescue Window::UnknownPeriod => e
          unknown_period(e)
        rescue Slice::InvalidFilters => e
          invalid_filters(e)
        end

        private

        def top(read, limit)
          result = AhoyDashboard::SearchConsoleQuery.call(
            range: read.range, limit: limit.to_i.clamp(1, 50)
          )
          queries = result.queries.map { |row| row_for(row) }

          drawn = result.connected ? draw_queries(read, queries) : { drawn: false }

          read.to_h.merge(unfiltered(read)).merge(
            connected: result.connected,
            note: "the totals are the whole site. the per query rows add up to less than that " \
                  "because google withholds rare queries, so never present them as a breakdown " \
                  "of the total.",
            **drawn,
            totals: { clicks: result.totals.clicks, impressions: result.totals.impressions },
            counted_in_the_rows: { clicks: result.coverage.counted_clicks,
                                   impressions: result.coverage.counted_impressions,
                                   withheld_clicks: result.coverage.missing_clicks,
                                   withheld_impressions: result.coverage.missing_impressions },
            queries: queries
          )
        end

        def keyword(read, query)
          result = AhoyDashboard::SearchConsoleKeywordQuery.call(keyword: query, range: read.range)
          days_read = result.days.map { |day| day_for(day) }

          drawn = draw_keyword(read, query, days_read)

          read.to_h.merge(unfiltered(read)).merge(
            keyword: query, recorded: result.recorded_days.size, **drawn,
            note: NO_POSITION,
            totals: { clicks: result.totals.clicks, impressions: result.totals.impressions,
                      position: position(result.totals.position, result.totals.impressions) },
            days: days_read
          )
        end

        def day_for(day)
          unless day.recorded?
            return { date: day.date, recorded: false, clicks: nil, impressions: nil, position: nil }
          end

          { date: day.date, recorded: true, clicks: day.clicks, impressions: day.impressions,
            position: position(day.position, day.impressions) }
        end

        def position(value, impressions)
          impressions.to_i.positive? ? rounded(value, 1) : nil
        end

        def keyword_rows(days_read)
          days_read.map do |day|
            shown = day.slice(:date, :clicks, :impressions, :position)
            day[:recorded] && day[:position].nil? ? shown.merge(position: NO_IMPRESSIONS) : shown
          end
        end

        def draw_queries(read, queries)
          show(
            View.table(
              title: "Searches on Google, #{read.label}",
              subtitle: unfiltered_subtitle("Position is an impression weighted average, not a rank", read),
              columns: [ { key: :query, label: "Search" },
                         { key: :clicks, label: "Clicks", align: "end" },
                         { key: :impressions, label: "Impressions", align: "end" },
                         { key: :position, label: "Avg position", align: "end" } ],
              rows: queries,
              path: routes.search_console_report_path(read.link_params),
              path_label: "Open the Search Console report"
            )
          )
        end

        def draw_keyword(read, query, days_read)
          show(
            View.table(
              title: "#{query}, #{read.label}",
              subtitle: unfiltered_subtitle("Position is an impression weighted average, not a rank", read),
              columns: [ { key: :date, label: "Day" },
                         { key: :clicks, label: "Clicks", align: "end" },
                         { key: :impressions, label: "Impressions", align: "end" },
                         { key: :position, label: "Avg position", align: "end" } ],
              rows: keyword_rows(days_read),
              path: routes.search_console_keyword_path(read.link_params(q: query)),
              path_label: "Open this search"
            )
          )
        end

        def row_for(row)
          { query: row.label, clicks: row.clicks, impressions: row.impressions,
            ctr: rounded(row.ctr, 4), position: rounded(row.position, 1) }
        end
      end
    end
  end
end
