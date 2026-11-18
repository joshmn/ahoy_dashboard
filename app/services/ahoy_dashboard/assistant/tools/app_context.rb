module AhoyDashboard
  module Assistant
    module Tools
      class AppContext < BaseTool
        label "where the screens are"

        SCREENS = {
          "dashboard" => { path: "",
                           does: "The visitor chart, the metric tiles and the report cards. Filters and the date range live here." },
          "explore" => { path: "explore",
                         does: "One composed question instead of the grid of pre-decided ones: pick a dimension, pick columns, page through the rows." },
          "funnels" => { path: "settings/funnels",
                         does: "Named sequences of goals, and how many people reached each step." },
          "goals" => { path: "settings/goals",
                       does: "Conversions worth naming. A goal added today reads the whole history that matches it." },
          "properties" => { path: "settings/properties",
                            does: "Which custom event properties get their own breakdown." },
          "segments" => { path: "settings/segments",
                          does: "Saved sets of filters, applied in one click." },
          "excluded traffic" => { path: "settings/exclusions",
                                  does: "Traffic left out of every number, like datacenter networks or scanners. Show hidden traffic brings it back." },
          "page groups" => { path: "settings/page_groups",
                             does: "Which noisy paths fold into one name on the pages card." },
          "annotations" => { path: "settings/annotations",
                             does: "What happened on a day, marked on the chart." },
          "search console" => { path: "search_console_report",
                                does: "Everything pulled from Google, at every grain it was pulled at. Position here is an average, not a rank." },
          "google account" => { path: "settings/google_connection",
                                does: "Connecting Search Console and picking which property it reads." },
          "rankings" => { path: "rankings",
                          does: "Where the site actually comes on the results page, who else is on page one, and what the AI overviews are quoting." },
          "rank tracking" => { path: "settings/serp_keywords",
                               does: "Which searches are checked, how often, how deep, and from where." },
          "import keywords" => { path: "settings/serp_keyword_import/new",
                                 does: "Take the busiest Search Console queries, or a pasted list, and start tracking all of them at once." },
          "sites" => { path: "settings/serp_sites",
                       does: "The domains looked for in the results: yours and anybody you want to watch." },
          "search provider" => { path: "settings/serp_providers",
                                 does: "Who runs the searches, their credentials, and the ceiling on what they may spend in a month." },
          "realtime" => { path: "realtime",
                          does: "Who is on the site right now." },
          "saved queries" => { path: "settings/saved_queries",
                               does: "Questions saved out of Explore, opened again on today's data." },
          "alert rules" => { path: "settings/alert_rules",
                             does: "Which alert rules are on and how serious each one is." },
          "jobs" => { path: "settings/job_runs",
                      does: "The background schedule: what runs, when it last ran, and a way to run it now." },
          "assistant" => { path: "settings/assistant_providers",
                           does: "Which model answers in Ask, and its key." },
          "ask" => { path: "chats",
                     does: "Every question asked so far, and a way to start a new one." },
          "SEO" => { path: "seo",
                     does: "How the site is doing in Google search, and what to work on next." },
          "visibility" => { path: "seo/visibility",
                            does: "A single score for how much of the tracked searches the site shows up in." },
          "position changes" => { path: "seo/position_change",
                                  does: "Tracked searches that moved up, moved down, showed up or dropped out." },
          "keyword gap" => { path: "seo/keyword_gap",
                             does: "Searches a competitor ranks for and the site does not, or ranks lower on." },
          "volatility" => { path: "seo/volatility",
                            does: "How much the results pages are shifting, and which searches moved most." },
          "SERP features" => { path: "seo/serp_feature",
                               does: "Snippets, knowledge panels, People also ask and related searches on the results pages." },
          "opportunities" => { path: "seo/opportunity",
                               does: "Searches where a better position would bring the most extra clicks." },
          "cannibalization" => { path: "seo/cannibalization",
                                 does: "Searches where more than one page on the site competes for the same spot." },
          "brand vs non-brand" => { path: "seo/brand_split",
                                    does: "Clicks from people searching the brand name apart from everyone else." },
          "search to conversion" => { path: "seo/conversion",
                                      does: "Which searches bring visitors who go on to complete a goal." },
          "AI visibility" => { path: "seo/ai_visibility",
                               does: "How often ChatGPT, Claude, Gemini and Perplexity mention or cite the site when asked the tracked prompts, and who they cite instead." },
          "AI visibility settings" => { path: "settings/ai_visibility",
                                        does: "The tracked prompts, how often they are asked, and the monthly cap on requests." },
          "keyword research" => { path: "seo/keyword_research",
                                  does: "Search volume, difficulty and intent for new keyword ideas." },
          "backlinks" => { path: "seo/backlink",
                           does: "Sites that link to this one, and which links are new or gone." },
          "SEO alerts" => { path: "seo/alert",
                            does: "Alerts that have fired, newest first." },
          "tracked keyword" => { path: "rank_keyword",
                                 does: "One tracked search over time: its position, who else ranks, and the AI overview." },
          "search console keyword" => { path: "search_console_keyword",
                                        does: "One search term's clicks, impressions and position from Google, day by day." }
        }.freeze

        desc "What a screen in AhoyDashboard is for and where it lives. Call this before explaining " \
             "how to do something, and link to the path it gives back."

        params do
          string :topic, description: "What the person is asking about, in their words. Leave it out for every screen.",
                         required: false
        end

        def execute(topic: nil)
          return { screens: everything } if topic.blank?

          matches = SCREENS.select { |name, screen| matches?(name, screen, topic) }
          return { screens: everything } if matches.empty?

          { screens: matches.map { |name, screen| entry(name, screen) } }
        end

        private

        def everything
          SCREENS.map { |name, screen| entry(name, screen) }
        end

        def entry(name, screen)
          { name: name, path: AhoyDashboard.mount_path(screen[:path]), does: screen[:does] }
        end

        def matches?(name, screen, topic)
          words = topic.to_s.downcase.scan(/[a-z]{3,}/)
          return false if words.empty?

          haystack = "#{name} #{screen[:does]}".downcase

          words.any? { |word| haystack.include?(word) }
        end
      end
    end
  end
end
