module AhoyDashboard
  module SearchConsoleScreen
    private

    def load_search_console_screen
      @connection = AhoyDashboard::Settings::GoogleConnectionPresenter.new(
        callback: SearchConsoleCallbackQuery.call(request: request), remove: params[:remove]
      )
      @confirming = params[:confirm].present?
      @redirect_form ||= SearchConsole::RedirectForm.current
    end
  end
end
