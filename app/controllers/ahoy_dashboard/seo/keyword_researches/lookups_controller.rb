module AhoyDashboard
  module Seo
    module KeywordResearches
      class LookupsController < BaseController
        def create
          form = KeywordLookupForm.new(params.permit(*KeywordLookupForm::FIELDS).to_h)
          seed = form.seed_value

          return redirect_to(seo_keyword_research_path(seed: seed.presence), alert: form.message) if form.invalid?

          picked = form.lookup_params

          blocker = AhoyDashboard::Keywords.refusal
          if blocker
            return redirect_to(seo_keyword_research_path(picked),
                               alert: AhoyDashboard::Keywords.refusal_message(blocker))
          end

          if AhoyDashboard::KeywordIdea.saved(seed, location: picked[:location], language: picked[:language]).exists?
            return redirect_to(seo_keyword_research_path(picked),
                               notice: "#{AhoyDashboard::KeywordIdea::Lookup.new(**picked).label} is already saved, " \
                                       "so nothing was bought. Press Look up again to pay for fresh numbers.")
          end

          AhoyDashboard::Keywords::FetchJob.perform_later(seed, location: picked[:location], language: picked[:language])

          redirect_to seo_keyword_research_path(picked),
                      notice: "Looking up #{seed}. Refresh in a moment."
        end

        private

        def surface_key
          "keyword_research"
        end
      end
    end
  end
end
