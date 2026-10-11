module AhoyDashboard
  module Seo
    module KeywordResearches
      class RefreshesController < BaseController
        def create
          form = KeywordLookupForm.from_params(params)
          seed = form.seed_value

          return redirect_to(seo_keyword_research_path(seed: seed.presence), alert: form.message) if form.invalid?

          picked = { seed: seed, location: form.location_value, language: form.language_value }

          blocker = AhoyDashboard::Keywords.refusal
          if blocker
            return redirect_to(seo_keyword_research_path(picked),
                               alert: AhoyDashboard::Keywords.refusal_message(blocker))
          end

          AhoyDashboard::Keywords::FetchJob.perform_later(seed, true, location: picked[:location], language: picked[:language])

          redirect_to seo_keyword_research_path(picked),
                      notice: "Looking up #{seed} again. Refresh in a moment."
        end

        private

        def surface_key
          "keyword_research"
        end
      end
    end
  end
end
