module AhoyDashboard
  class AssetsController < AhoyDashboard::BaseController
    # Rails refuses to serve a text/javascript body to a plain GET, on the
    # grounds that a dynamic script could be read cross origin by a script tag.
    # These are static files with nothing in them to leak, and a script tag is
    # exactly how they are asked for.
    skip_after_action :verify_same_origin_request, raise: false

    def show
      file = AhoyDashboard::Assets.resolve(params[:path])

      if params[:build] == AhoyDashboard::Assets.build
        expires_in 1.year, public: false, immutable: true
      else
        expires_now
      end

      send_file file, type: AhoyDashboard::Assets.content_type(file), disposition: :inline
    rescue AhoyDashboard::Assets::UnknownAsset
      raise ActiveRecord::RecordNotFound
    end
  end
end
