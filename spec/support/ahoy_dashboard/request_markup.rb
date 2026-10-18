module AhoyDashboardRequestMarkup
  def expect_sound_markup(status: :ok)
    page = document
    ids = page.css("[id]").map { |node| node["id"] }
    references = page.css("[aria-labelledby], [aria-describedby]").flat_map do |node|
      [ node["aria-labelledby"], node["aria-describedby"] ].compact.flat_map(&:split)
    end
    unnamed = page.css("button:not([aria-hidden=true])").reject do |button|
      button.text.strip.present? || button["aria-label"].present? || button["title"].present?
    end

    expect(response).to have_http_status(status)
    expect(page.css("h1").size).to eq(1)
    expect(ids.group_by { |item| item }.transform_values(&:size).select { |_, count| count > 1 }.keys).to be_empty
    expect(references - ids).to be_empty
    expect(page.css("label[for]").map { |label| label["for"] } - ids).to be_empty
    expect(unnamed.map(&:to_html)).to be_empty
  end
end

RSpec.configure { |config| config.include AhoyDashboardRequestMarkup, type: :request }
