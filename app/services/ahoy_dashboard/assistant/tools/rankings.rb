module AhoyDashboard
  module Assistant
    module Tools
      class Rankings < BaseTool
        label "the rank tracking"

        def self.feature
          :serp
        end

        desc "Call this for where the site actually placed on Google's results page for the searches " \
             "being tracked, and whether the AI overview cited it. One integer per search from the rank " \
             "tracker, not an average. For queries, clicks and impressions from Google, call search_console instead."

        params do
          string :query, description: "One tracked search to read the history of. Leave it out for every tracked search.",
                         required: false
          AhoyDashboard::Assistant::Tools::BaseTool.window_params(self)
        end

        private

        def answer(query: nil, **asked)
          site = AhoyDashboard::SerpSite.ours
          return not_ours if site.nil?

          read = window(**asked)

          query.present? ? one(read, query, site) : all(read, site)
        end

        def not_ours
          sites = AhoyDashboard::SerpSite.pluck(:domain)
          return { error: "no site is set up to look for in the results" } if sites.empty?

          { error: "no tracked site is this one (#{AhoyDashboard::Serp.own_domain.presence || "no host is configured"}), " \
                   "so there is no ranking of ours to read. the sites tracked are competitors, and their " \
                   "positions must never be passed off as this site's.",
            tracked_sites: sites }
        end

        def all(read, site)
          result = AhoyDashboard::Serp::RankOverviewQuery.call(site: site, range: read.range)
          searches = result.rows.map do |row|
            { query: row.keyword.query, place: row.location, position: row.position,
              change: row.change, best: row.best, url: row.url, cited: row.cited? }
          end

          drawn = draw_all(read, searches)

          read.to_h.merge(unfiltered(read)).merge(
            **drawn, site: site.domain, tracked: result.tracked,
            ranking: result.ranked, top_ten: result.top_ten, top_three: result.top_three,
            median_position: result.median, overviews_seen: result.overviews,
            overviews_citing_us: result.cited, searches: searches
          )
        end

        def one(read, query, site)
          keyword = AhoyDashboard::Serp::KeywordLookupQuery.call(text: query)
          return { error: "#{query} is not tracked", tracked: AhoyDashboard::SerpKeyword.pluck(:query) } if keyword.nil?

          result = AhoyDashboard::Serp::KeywordSeriesQuery.call(
            keyword: keyword, site: site, range: read.range
          )
          readings = result.points.map do |point|
            { at: point.at, position: point.position, cited: point.cited }
          end

          drawn = draw_one(read, keyword, readings)

          read.to_h.merge(unfiltered(read)).merge(
            keyword: keyword.query, place: result.location, position: result.position,
            best: result.best, worst: result.worst, change: result.change,
            **drawn, readings: readings
          )
        end

        def draw_all(read, searches)
          show(
            View.table(
              title: "Tracked searches, #{read.label}",
              subtitle: unfiltered_subtitle("One integer per search, not an average", read),
              columns: [ { key: :query, label: "Search" },
                         { key: :place, label: "Place" },
                         { key: :position, label: "Position", align: "end" },
                         { key: :best, label: "Best", align: "end" } ],
              rows: searches,
              path: routes.rankings_path(read.link_params),
              path_label: "Open the rankings"
            )
          )
        end

        def draw_one(read, keyword, readings)
          show(
            View.table(
              title: "#{keyword.query}, #{read.label}",
              subtitle: unfiltered_subtitle("Where the site came on the results page", read),
              columns: [ { key: :at, label: "Checked" },
                         { key: :position, label: "Position", align: "end" } ],
              rows: readings,
              path: routes.rank_keyword_path(read.link_params(keyword: keyword.id)),
              path_label: "Open this search"
            )
          )
        end
      end
    end
  end
end
