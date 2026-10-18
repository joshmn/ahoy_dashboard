module AhoyDashboard
  class FaviconsController < AhoyDashboard::BaseController
    MAX_AGE = 7.days
    FALLBACK = ["47494638396101000100800000000000ffffff21f90401000000002c00000000010001000002024401003b"].pack("H*").freeze

    def show
      domain = AhoyDashboard::FaviconService.accept(params[:site])
      raise ActiveRecord::RecordNotFound if domain.nil? || !AhoyDashboard::FaviconService.enabled?

      icon = AhoyDashboard::FaviconService.new(domain).cached
      if icon.nil?
        AhoyDashboard::FaviconEnqueueService.call(domain: domain)
        expires_in 1.minute, public: false
        return send_data(FALLBACK, type: "image/gif", disposition: "inline")
      end

      expires_in MAX_AGE, public: false
      send_data icon.bytes, type: icon.content_type, disposition: "inline"
    end
  end
end
