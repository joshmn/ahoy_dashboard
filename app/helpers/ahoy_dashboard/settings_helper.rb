module AhoyDashboard
  module SettingsHelper
    def dash_delete_confirm(name, consequence, url:, cancel:, span:)
      message = safe_join([ "Delete ", tag.b(name), "? ", consequence ])

      dash_table_confirm(message, span: span, cancel: cancel) do
        dash_button_to("Delete", url, method: :delete, tone: :danger)
      end
    end

    def dash_move_buttons(url, name:, param:, index:, count:)
      safe_join([
        dash_icon_button_to(:chevron_up, url, label: "Move #{name} up the list", method: :patch,
                                              params: { param => { nudge: "up" } }, disabled: index.zero?),
        dash_icon_button_to(:chevron_down, url, label: "Move #{name} down the list", method: :patch,
                                                params: { param => { nudge: "down" } }, disabled: index == count - 1)
      ], " ")
    end

    def dash_edit_button(name, url, **options)
      dash_icon_button(:gear, label: "Edit #{name}", url: url, title: "Edit", **options)
    end

    def dash_delete_button(name, url, **options)
      dash_icon_button(:close, label: "Delete #{name}", url: url, tone: :danger, title: "Delete", **options)
    end

    def dash_keyword_form_data(plan, limit: nil)
      {
        controller: "dash--keyword-form",
        action: "change->dash--keyword-form#refresh input->dash--keyword-form#refresh",
        "dash--keyword-form-costs-value": plan.costs.to_json,
        "dash--keyword-form-durations-value": plan.durations.to_json,
        "dash--keyword-form-month-value": AhoyDashboard::Settings::KeywordPlanPresenter::MONTH.to_i,
        "dash--keyword-form-limit-value": limit,
        "dash--keyword-form-remaining-value": (plan.remaining if plan.capped?)
      }
    end
  end
end
