module AhoyDashboard
  module Assistant
    module Tools
      class ProposePrompts < BaseTool
        MAX = 10
        BECAUSE_LENGTH = 300

        label "prompt suggestions"

        def self.feature
          :ai_visibility
        end

        def self.available?
          AiVisibility.enabled?
        end

        desc "Call this to put suggested AI visibility prompts in front of the person, each with a button that " \
             "adds it to the tracked set. Call prompt_evidence first, then call this once with every suggestion " \
             "rather than listing them in the answer. Nothing is added until the person clicks. It hands back " \
             "which ones were shown, which were turned away and why, and what each one would cost to ask."

        params do
          array :prompts, description: "Up to #{MAX} suggestions, best first.",
                          items: {
                            "type" => "object",
                            "properties" => {
                              "text" => { "type" => "string",
                                          "description" => "The whole question, as a person would type it into a chat box. " \
                                                           "At most #{AiVisibility::Prompt::MAX_LENGTH} characters." },
                              "because" => { "type" => "string",
                                             "description" => "One sentence naming the evidence row it came from, " \
                                                              "like the page, search or term and its count." }
                            },
                            "required" => %w[text because]
                          }
        end

        private

        def answer(prompts: [])
          room = AiVisibility::SettingsForm::MAX_PROMPTS - AiVisibility::Prompt.count
          shown, turned_away = sort(Array(prompts), room)

          drawn = draw(shown)

          {
            **drawn,
            shown: shown.map { |row| row.slice(:text, :names_the_site) },
            turned_away: turned_away.presence,
            cost: cost(shown.size),
            note: note(shown, drawn)
          }.compact
        end

        def sort(prompts, room)
          tracked = AiVisibility::Prompt.pluck(:text).map { |text| fold(text) }
          seen = []
          shown = []
          turned_away = []

          prompts.each do |raw|
            entry = raw.respond_to?(:to_h) ? raw.to_h.transform_keys(&:to_s) : {}
            text = entry["text"].to_s.squish
            reason = refusal(text, tracked: tracked, seen: seen, shown: shown.size, room: room)

            if reason
              turned_away << { text: text.presence || "(blank)", why: reason }
            else
              seen << fold(text)
              shown << { text: text, because: entry["because"].to_s.squish.first(BECAUSE_LENGTH).presence,
                         names_the_site: names_the_site?(text) }
            end
          end

          [ shown, turned_away ]
        end

        def refusal(text, tracked:, seen:, shown:, room:)
          return "it is blank" if text.blank?
          return "it is longer than #{AiVisibility::Prompt::MAX_LENGTH} characters" if text.length > AiVisibility::Prompt::MAX_LENGTH
          return "it is already tracked" if tracked.include?(fold(text))
          return "it repeats another suggestion" if seen.include?(fold(text))
          return "only #{MAX} are shown at once" if shown >= MAX
          return "the set is full at #{AiVisibility::SettingsForm::MAX_PROMPTS} prompts" if shown >= room

          nil
        end

        def fold(text)
          text.to_s.squish.downcase
        end

        def names_the_site?(text)
          folded = Seo::BrandTerms.fold(text)
          needles = [ Serp.own_domain, *Seo::BrandTerms.current ].map { |term| Seo::BrandTerms.fold(term) }.reject(&:blank?)

          needles.any? { |needle| folded.include?(needle) }
        end

        def cost(count)
          targets = AiVisibility.targets.size

          {
            assistants_and_models_asked: targets,
            requests_per_run_each: targets,
            how_often: AiVisibility::FREQUENCIES.fetch(AiVisibility.frequency)[:label].downcase,
            requests_a_month_for_all_shown: AiVisibility.monthly_requests(count, targets: targets),
            monthly_cap: AiVisibility.capped? ? AiVisibility.monthly_cap : "none",
            used_this_month: AiVisibility.used_this_month
          }
        end

        def note(shown, drawn)
          return "nothing was shown. rewrite the ones that were turned away, or say why there are none." if shown.empty?

          parts = []
          if drawn[:drawn]
            parts << "the suggestions are on the screen with their reasons and an add button each, so do not list them again"
          else
            parts << "the suggestions are not on the screen, so list them in the answer"
          end
          if shown.any? { |row| row[:names_the_site] }
            parts << "names_the_site true means it has the site's own name in it, which makes a mention easy and tells " \
                     "little, so say that if you keep it"
          end
          parts.join(". ")
        end

        def draw(shown)
          return { drawn: false } if shown.empty?

          show(View.prompts(title: "Prompts to track", subtitle: "Suggested from your converting visitors",
                            rows: shown))
        end
      end
    end
  end
end
