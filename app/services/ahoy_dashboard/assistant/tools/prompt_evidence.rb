module AhoyDashboard
  module Assistant
    module Tools
      class PromptEvidence < BaseTool
        DEFAULT_LIMIT = 10
        REPORT_DAYS = 90
        CITED_LIMIT = 10
        MISSING_LIMIT = 10

        ANCHORS = {
          AiVisibility::ConversionEvidenceQuery::GOAL => "completing a goal",
          AiVisibility::ConversionEvidenceQuery::SIGN_IN => "signing in for the first time"
        }.freeze

        label "what converting visitors did first"

        def self.feature
          :ai_visibility
        end

        def self.available?
          AiVisibility.enabled?
        end

        desc "Call this before suggesting prompts for AI visibility, the questions this site has ChatGPT, " \
             "Claude, Gemini and Perplexity asked on a schedule. It works backwards from the visitors who " \
             "converted: how they first arrived, the pages they landed on, the Google searches behind those " \
             "pages, paid search terms, the pages they read before converting that other visitors read less, " \
             "and the pages AI assistants already send people to. It also hands back the prompts already " \
             "tracked, the ones no assistant mentions the site in, and who gets cited instead. None of it is " \
             "what anybody typed into an assistant; that is never recorded. After reading it, call " \
             "propose_prompts with the suggestions."

        params do
          string :goal, description: "The name of one goal to work back from. Leave it out for every goal.",
                        required: false
          integer :limit, description: "How many rows in each list, from 1 to 25. Defaults to 10.", required: false
          AhoyDashboard::Assistant::Tools::BaseTool.window_params(self)
        end

        private

        def answer(goal: nil, limit: DEFAULT_LIMIT, **asked)
          found = find_goal(goal)
          return { error: "no goal called #{goal}", goals: goal_names } if goal.present? && found.nil?

          read = window(**asked)
          result = AiVisibility::ConversionEvidenceQuery.call(scope: read.scope, goal: found, limit: row_limit(limit))
          return unanchored(read) unless result.anchored?

          drawn = draw(read, result)

          read.to_h.merge(
            anchor: ANCHORS.fetch(result.anchor),
            goal: found&.name || ("any goal" if result.anchor == AiVisibility::ConversionEvidenceQuery::GOAL),
            looked_back: "#{result.lookback_days} days before each conversion, including before the window",
            converters: result.converters,
            other_visitors: result.others,
            thin: thin_note(result),
            **drawn,
            **evidence(result),
            tracking: tracking,
            how_to_write_them: rules
          ).compact
        end

        def find_goal(name)
          return nil if name.blank?

          AhoyDashboard::Goal.ordered.to_a.find { |candidate| candidate.name.casecmp?(name.to_s.strip) }
        end

        def goal_names
          AhoyDashboard::Goal.ordered.map(&:name)
        end

        def unanchored(read)
          read.to_h.merge(
            error: "there is nothing to work back from. no goal is set up, and ahoy_visits has no user_id " \
                   "column to tell when somebody signed in.",
            fix: "add a goal on the goals screen, then ask again"
          )
        end

        def thin_note(result)
          return nil unless result.thin?

          "only #{result.converters} visitors converted in this window. that is too few to read a pattern " \
            "from, so say so plainly, suggest a longer window, and suggest no more than a couple of prompts, " \
            "each one tied to a row below."
        end

        def evidence(result)
          {}.tap do |found|
            found[:first_arrived_through] = counts(result.channels) unless withheld?("channel")
            unless withheld?("entry_page")
              found[:landed_on] = entry_rows(result)
              found[:search_console] = search_console_note(result)
              found[:ai_assistants_send_people_to] = ai_rows(result)
            end
            found[:paid_search_terms] = counts(result.paid_terms) unless withheld?("utm_term")
            found[:read_before_converting] = viewed_rows(result) unless withheld?("page")
            found[:withheld] = withheld_note
          end.compact
        end

        def withheld?(key)
          Assistant.withheld?(key)
        end

        def withheld_note
          kept = %w[channel entry_page utm_term page].select { |key| withheld?(key) }
          return nil if kept.empty?

          "the site's owner keeps #{kept.join(", ")} out of the assistant, so those lists are left out"
        end

        def counts(rows)
          rows.map { |row| { name: row.label, converters: row.converters } }
        end

        def entry_rows(result)
          result.entry_pages.map do |page|
            { page: page.path, first_visit_landed_here: page.first_touch, any_visit_landed_here: page.any_touch,
              google_searches_landing_here: page.searches.map(&:query) }
          end
        end

        def search_console_note(result)
          return "search console is not set up, so there are no real search words to go on" unless result.search_console

          "google_searches_landing_here are the top searches anyone clicked through to that page on in this " \
            "window, not the searches these converters made. they are the nearest thing to real wording here."
        end

        def ai_rows(result)
          result.ai_landings.map do |landing|
            { page: landing.path, visitors: landing.visitors, converters: landing.converters,
              from: landing.assistants }
          end
        end

        def viewed_rows(result)
          result.before_conversion.map do |row|
            { page: row.path, converters_who_read_it: row.converters,
              share_of_converters: rounded(row.converter_share, 3),
              share_of_everyone_else: rounded(row.other_share, 3),
              times_as_likely: row.lift && rounded(row.lift, 1) }
          end
        end

        def tracking
          prompts = AiVisibility::Prompt.ordered.pluck(:text)
          base = {
            prompts: prompts,
            room_for: AiVisibility::SettingsForm::MAX_PROMPTS - prompts.size,
            brand_terms: Seo::BrandTerms.current,
            assistants_asked: AiVisibility.targets.map(&:label)
          }
          return base unless AiVisibility::Answer.exists?

          report = AiVisibility::ReportQuery.call(range: (REPORT_DAYS.days.ago.beginning_of_day)..Time.current)
          base.merge(
            not_mentioned_in: report.missing_prompts.first(MISSING_LIMIT).map { |row| row.prompt.text },
            cited_instead: report.cited_instead.first(CITED_LIMIT).map { |row| { domain: row.domain, answers: row.answers } }
          )
        end

        def rules
          "write each prompt as a whole question a person would type into a chat box, the way they would " \
            "ask it before they had heard of this site, so leave the brand terms out. tie each one to a row " \
            "above and say which in because. lean on google_searches_landing_here and paid_search_terms for " \
            "wording, read_before_converting for what they needed to know, and cited_instead for ground the " \
            "site is losing. skip anything already in prompts. every prompt is asked of every assistant on " \
            "every run and costs money, so offer a handful of good ones rather than many."
        end

        def draw(read, result)
          return { drawn: false } if withheld?("entry_page")

          show(
            View.table(
              title: "Where converters first landed, #{read.label}",
              subtitle: subtitle("Working back from #{ANCHORS.fetch(result.anchor)}", read: read),
              columns: [ { key: :page, label: "Page" },
                         { key: :first, label: "First visit", align: "end" },
                         { key: :any, label: "Any visit", align: "end" } ],
              rows: result.entry_pages.map { |page| { page: page.path, first: page.first_touch, any: page.any_touch } }
            )
          )
        end
      end
    end
  end
end
