require "rails_helper"

RSpec.describe AhoyDashboard::ComponentsHelper, type: :helper do
  before { helper.extend(AhoyDashboard::DashboardHelper) }

  def html(markup)
    Nokogiri::HTML5.fragment(markup)
  end

  describe "#dash_button" do
    it "is a link when it has somewhere to go and a button when it does not" do
      link = html(helper.dash_button("Export", "/export", icon: :download)).at_css("a")
      button = html(helper.dash_button("Find", type: "submit", tone: :primary)).at_css("button")

      expect(link["href"]).to eq("/export")
      expect(link.at_css("svg|svg", "svg" => "http://www.w3.org/2000/svg")["aria-hidden"]).to eq("true")
      expect(link.text.strip).to eq("Export")
      expect(button["type"]).to eq("submit")
      expect(button.text).to eq("Find")
    end

    it "takes its content from a block, with the url first" do
      link = html(helper.dash_button("/settings", "aria-current": "page") { "Settings" }).at_css("a")

      expect(link["href"]).to eq("/settings")
      expect(link["aria-current"]).to eq("page")
      expect(link.text).to eq("Settings")
    end

    it "refuses a tone the kit does not have" do
      expect { helper.dash_button("Odd", tone: :purple) }.to raise_error(KeyError)
    end
  end

  describe "#dash_icon_button" do
    it "names itself for a screen reader" do
      button = html(helper.dash_icon_button(:gear, label: "Settings")).at_css("button")

      expect(button["aria-label"]).to eq("Settings")
      expect(button["type"]).to eq("button")
    end
  end

  describe "#dash_toggle_icon_button" do
    it "is a named toggle that starts unpressed" do
      button = html(helper.dash_toggle_icon_button(off: :expand, on: :collapse, label: "Full screen")).at_css("button")

      expect(button["aria-label"]).to eq("Full screen")
      expect(button["aria-pressed"]).to eq("false")
      expect(button["type"]).to eq("button")
      expect(button.css("svg|svg[aria-hidden=true]", "svg" => "http://www.w3.org/2000/svg").size).to eq(2)
    end

    it "can start pressed" do
      button = html(helper.dash_toggle_icon_button(off: :expand, on: :collapse, label: "Full screen", pressed: true))
        .at_css("button")

      expect(button["aria-pressed"]).to eq("true")
    end
  end

  describe "#dash_button_to" do
    it "asks before it submits when told to" do
      form = html(helper.dash_button_to("Delete", "/goals/1", method: :delete, tone: :danger, confirm: "Delete Signups?")).at_css("form")

      expect(form["action"]).to eq("/goals/1")
      expect(form.at_css("input[name=_method]")["value"]).to eq("delete")
      expect(form.at_css("button")["data-tm-confirm"]).to eq("Delete Signups?")
    end

    it "says why it cannot be pressed instead of submitting" do
      markup = html(helper.dash_button_to("Check now", "/check", reason: "This keyword is paused."))
      button = markup.at_css("button[disabled]")
      why = markup.at_css("##{button['aria-describedby']}")

      expect(markup.at_css("form")).to be_nil
      expect(button.text).to eq("Check now")
      expect(why.text.squish).to eq("This keyword is paused.")
      expect(markup.at_css(".btn-reason")["title"]).to eq("This keyword is paused.")
    end
  end

  describe "#dash_badge" do
    it "shows its label and passes attributes through" do
      badge = html(helper.dash_badge("Paused", title: "Not being checked")).at_css("span")

      expect(badge["title"]).to eq("Not being checked")
      expect(badge.text).to eq("Paused")
    end

    it "takes a block for the contents" do
      expect(html(helper.dash_badge(tone: :success) { "up 5" }).at_css("span").text).to eq("up 5")
    end

    it "refuses a tone the kit does not have" do
      expect { helper.dash_badge("Odd", tone: :purple) }.to raise_error(KeyError)
    end
  end

  describe "#dash_notice" do
    it "leads with the title in bold, then the detail, then the one button that fixes it" do
      alert = html(helper.dash_notice("Search Console is not syncing.", tone: :warning,
                                      action: helper.dash_button("Fix connection", "/google")) { "Google refused the last sync." })
        .at_css("[role=status]")

      expect(alert.at_css("p").text.squish).to eq("Search Console is not syncing. Google refused the last sync.")
      expect(alert.at_css("p b").text).to eq("Search Console is not syncing.")
      expect(alert.at_css("a")["href"]).to eq("/google")
      expect(alert.text.squish).to eq("Search Console is not syncing. Google refused the last sync. Fix connection")
    end

    it "takes the detail on its own, and interrupts when something has stopped" do
      alert = html(helper.dash_notice(detail: "Nothing was saved.", tone: :danger)).at_css("div")

      expect(alert["role"]).to eq("alert")
      expect(alert.at_css("b")).to be_nil
      expect(alert.text).to eq("Nothing was saved.")
    end

    it "refuses a tone the kit does not have" do
      expect { helper.dash_notice("Odd", tone: :success) }.to raise_error(KeyError)
    end
  end

  describe "#dash_toast" do
    it "says what happened and offers a way to dismiss it" do
      toast = html(helper.dash_toast("Saved.")).at_css("[data-controller='dash--toast']")
      close = toast.at_css("button")

      expect(toast["role"]).to eq("status")
      expect(toast["data-dash--toast-delay-value"]).to be_nil
      expect(toast.text.strip).to eq("Saved.")
      expect(close["aria-label"]).to eq("Dismiss")
      expect(close["data-action"]).to eq("dash--toast#dismiss")
    end

    it "keeps an error up longer and reads it out straight away" do
      toast = html(helper.dash_toast("That did not save.", tone: :danger)).at_css("[data-controller='dash--toast']")

      expect(toast["role"]).to eq("alert")
      expect(toast["data-dash--toast-delay-value"]).to eq("6000")
    end
  end

  describe "#dash_empty" do
    it "says what is missing, why, and offers the buttons that fill it" do
      empty = html(helper.dash_empty("No keywords yet", hint: "Track a search to see where you rank.",
                                     action: { label: "Track keyword", url: "/keywords/new" },
                                     secondary: { label: "Import", url: "/imports/new" }))

      expect(empty.css("p").map(&:text)).to eq([ "No keywords yet", "Track a search to see where you rank." ])
      expect(empty.css("a").map { |link| [ link.text, link["href"] ] })
        .to eq([ [ "Track keyword", "/keywords/new" ], [ "Import", "/imports/new" ] ])
    end

    it "takes a presenter's hash as it is, and leaves out a blank hint" do
      notice = { title: "No backlinks yet", hint: "", action: { label: "Providers", url: "/providers", data: { tm_frame: "_top" } } }
      empty = html(helper.dash_empty(**notice, compact: true, role: "status"))

      expect(empty.at_css("[role=status]")).to be_present
      expect(empty.css("p").map(&:text)).to eq([ "No backlinks yet" ])
      expect(empty.at_css("a")["data-tm-frame"]).to eq("_top")
    end
  end

  describe "#dash_page_head" do
    it "opens with the way back, the title, what the page is, and its buttons" do
      head = html(helper.dash_page_head("botnet takedown", back: { label: "Rank tracking", url: "/rankings" },
                                        lede: "Checked daily.") { helper.dash_button("Edit keyword", "/edit") })
        .at_css("header")
      back, edit = head.css("a")

      expect([ back["href"], back.text, back["data-tm-frame"] ]).to eq([ "/rankings", "Rank tracking", "_top" ])
      expect(head.at_css("h1").text).to eq("botnet takedown")
      expect(head.at_css("h1 + p").text).to eq("Checked daily.")
      expect([ edit["href"], edit.text ]).to eq([ "/edit", "Edit keyword" ])
    end

    it "keeps the whole title in the heading and lets the page clip it when asked" do
      heading = html(helper.dash_page_head(title: "a very long question about last month", clip: true)).at_css("h1")

      expect(heading.text).to eq("a very long question about last month")
      expect(heading["title"]).to eq("a very long question about last month")
      expect(html(helper.dash_page_head(title: "Goals")).at_css("h1")["title"]).to be_nil
    end

    it "takes the title and actions as keywords, a plain kicker, and leaves out what it is not given" do
      head = html(helper.dash_page_head(title: "Goals", kicker: "Settings", lede: "",
                                        actions: helper.dash_button("New goal", "/goals/new"))).at_css("header")

      expect(head.css("p").map(&:text)).to eq([ "Settings" ])
      expect(head.at_css("h1").text).to eq("Goals")
      expect(head.at_css("a").text).to eq("New goal")
    end
  end

  describe "#dash_form_with" do
    let(:form_class) do
      Class.new do
        include ActiveModel::Model

        attr_accessor :query, :threshold, :frequency, :enabled, :site_ids, :site_id

        def self.model_name
          ActiveModel::Name.new(self, nil, "Keyword")
        end
      end
    end
    let(:keyword) { form_class.new(query: "botnet takedown", frequency: "weekly", site_ids: [ "2" ]) }

    def form(&block)
      html(helper.dash_form_with(model: keyword, url: "/keywords", &block))
    end

    it "writes the label, hint, error and the wiring between them" do
      keyword.errors.add(:query, "You already track this search.")
      markup = form { |f| f.text_field :query, label: "Keyword", hint: "Exactly what someone types." }
      input = markup.at_css("input#keyword_query")

      expect(markup.at_css("label[for=keyword_query]").text).to eq("Keyword")
      expect(input["name"]).to eq("keyword[query]")
      expect(input["aria-invalid"]).to eq("true")
      expect(input["aria-describedby"]).to eq("keyword_query_hint keyword_query_error")
      expect(markup.at_css("#keyword_query_error").text).to eq("You already track this search.")
      expect(markup.at_css("#keyword_query_hint").text).to eq("Exactly what someone types.")
    end

    it "leaves a control bare when it has no label, and says when a field is optional" do
      markup = form do |f|
        f.text_field(:query) + f.number_field(:threshold, label: "Alert when it falls", optional: true, suffix: "places")
      end
      threshold = markup.at_css("label[for=keyword_threshold]").parent

      expect(markup.at_css("input#keyword_query").parent.name).to eq("form")
      expect(markup.at_css("input#keyword_query")["aria-invalid"]).to be_nil
      expect(markup.at_css("label[for=keyword_threshold]").text.squish).to eq("Alert when it falls (optional)")
      expect(threshold.text).to include("places")
    end

    it "puts attributes on the field's wrapper, for a page that hides one field for another" do
      markup = form { |f| f.text_field(:query, label: "Event name", wrapper: { data: { kind: "event" } }) }

      expect(markup.at_css("input#keyword_query").parent["data-kind"]).to eq("event")
    end

    it "sums up the errors at the top, linking each one to its field" do
      keyword.errors.add(:base, "Rank tracking is off.")
      keyword.errors.add(:threshold, "Pick a number between 1 and 100.")
      keyword.errors.add(:query, "has to be typed")
      markup = form { |f| f.error_summary + f.text_field(:query, label: "Keyword") }
      summary = markup.at_css("[role=alert]")

      expect(summary.at_css("p").text).to eq("That did not save.")
      expect(summary.css("li").map(&:text)).to eq([ "Rank tracking is off.", "Pick a number between 1 and 100.", "Query has to be typed" ])
      expect(summary.css("li a").map { |link| link["href"] }).to eq(%w[#keyword_threshold #keyword_query])
      expect(markup.at_css("#keyword_query_error").text).to eq("Has to be typed")
      expect(html(helper.dash_form_with(model: form_class.new, url: "/k", &:error_summary)).at_css("[role=alert]")).to be_nil
    end

    it "ends on the submit button that says what it does, and the way out" do
      markup = form { |f| f.select(:site_id, [ [ "Us", "1" ] ], {}, label: "Site") + f.actions("Save keyword", cancel: "/keywords") }

      expect(markup.at_css("label[for=keyword_site_id]").text).to eq("Site")
      expect(markup.css("select#keyword_site_id option").map(&:text)).to eq([ "Us" ])
      expect(markup.at_css("input[type=submit]")["value"]).to eq("Save keyword")
      expect(markup.at_css("a[href='/keywords']").text).to eq("Cancel")
    end

    it "groups choices under a legend: segmented, radios, check boxes and a switch" do
      sites = [ Struct.new(:id, :name, :domain).new(2, "Us", "example.com") ]
      markup = form do |f|
        f.segmented(:frequency, [ [ "daily", "Daily" ], [ "weekly", "Weekly" ] ], label: "How often", hint: "Weekly is enough.") +
          f.radio_group(:threshold, %w[drop fall], label: "Fires when") +
          f.check_boxes(:site_ids, sites, ->(site) { site.id.to_s }, :name, label: "Look for", detail: :domain.to_proc) +
          f.switch(:enabled, label: "Track this keyword")
      end
      how_often, fires_when, look_for = markup.css("fieldset")

      expect(how_often["aria-describedby"]).to eq("keyword_frequency_hint")
      expect(how_often.at_css("legend").text).to eq("How often")
      expect(how_often.css("input[type=radio]").map { |radio| radio["value"] }).to eq(%w[daily weekly])
      expect(how_often.at_css("input[checked]")["value"]).to eq("weekly")
      expect(how_often.at_css("label[for=keyword_frequency_weekly]").text).to eq("Weekly")
      expect(fires_when.css("label").map(&:text)).to eq(%w[Drop Fall])
      expect(look_for.at_css("label").text.squish).to eq("Us example.com")
      expect(look_for.at_css("input[value='2']")["checked"]).to be_present
      expect(markup.at_css("input#keyword_enabled")["role"]).to eq("switch")
    end
  end

  describe "#dash_card" do
    it "is one titled block: a head with the title and its controls, the content, and a note at the foot" do
      section = html(helper.dash_card(element: :section, "aria-labelledby": "top-title") do
        helper.dash_card_header("Top searches", id: "top-title") { helper.tag.span("Last 30 days") } +
          helper.tag.ul("rows") +
          helper.dash_card_footer { "Search Console runs two days behind." }
      end).at_css("section")

      expect(section["aria-labelledby"]).to eq("top-title")
      expect(section.at_css("h2#top-title").text).to eq("Top searches")
      expect(section.children.map(&:text)).to eq([ "Top searchesLast 30 days", "rows", "Search Console runs two days behind." ])
    end

    it "leaves the title out of a head that has none, and puts a button foot in a footer" do
      head = html(helper.dash_card_header(element: :header) { "Controls" }).at_css("header")
      foot = html(helper.dash_card_footer(action: true) { helper.dash_button("Show all", "/all", tone: :link) }).at_css("footer")

      expect(head.at_css("h2")).to be_nil
      expect(head.text).to eq("Controls")
      expect(foot.at_css("a")["href"]).to eq("/all")
    end
  end

  describe "#dash_tabs" do
    it "marks the tab showing, and wires the card's tab controller when asked" do
      nav = html(helper.dash_tabs([ { label: "Queries", url: "/q", current: true },
                                    { label: "Pages", url: "/p", data: { tm_frame: "gsc" } } ],
                                  label: "Show", select: true)).at_css("nav")

      expect(nav["aria-label"]).to eq("Show")
      expect(nav["data-action"]).to eq("keydown->dash--tabs#navigate")
      expect(nav.css("a").map { |link| [ link.text, link["href"], link["aria-current"], link["data-action"] ] })
        .to eq([ [ "Queries", "/q", "true", "dash--tabs#select" ], [ "Pages", "/p", nil, "dash--tabs#select" ] ])
      expect(nav.css("a").last["data-tm-frame"]).to eq("gsc")
    end

    it "is plain links in a dialog, with no controller hooks" do
      nav = html(helper.dash_tabs([ { label: "Queries", url: "/q" } ], label: "Views")).at_css("nav")

      expect(nav["data-action"]).to be_nil
      expect(nav.at_css("a")["data-action"]).to be_nil
    end
  end

  describe "#dash_card_header" do
    it "renders no slot for controls when the block has none to give" do
      head = html(helper.dash_card_header("Goals") { "" })

      expect(head.at_css("h2").text).to eq("Goals")
      expect(head.at_css("h2").next_element).to be_nil
    end
  end

  describe "#dash_table" do
    it "is a table inside a named group a keyboard can scroll, one column for each track" do
      markup = html(helper.dash_table(label: "Goals", cols: "minmax(0, 1fr) 104px 64px") do
        helper.tag.tbody(helper.tag.tr(helper.tag.td("Signup")))
      end)
      group = markup.at_css("div[role=group]")

      expect([ group["aria-label"], group["tabindex"] ]).to eq([ "Goals", "0" ])
      expect(group.css("table > colgroup > col").size).to eq(3)
      expect(group.at_css("table tbody td").text).to eq("Signup")
    end

    it "is a landmark region when the table is the page's own result" do
      group = html(helper.dash_table(label: "Result, scrolls sideways", region: true) { helper.tag.tbody }).at_css("div[tabindex]")

      expect(group["role"]).to eq("region")
      expect(group["aria-label"]).to eq("Result, scrolls sideways")
    end

    it "asks before a delete in a row that spans every column" do
      message = helper.safe_join([ "Delete ", helper.tag.b("Signup"), "? Past conversions stay." ])
      confirm = helper.dash_table_confirm(message, span: 5) { helper.dash_button("Cancel", "/goals", tone: :link) }
      row = html("<table><tbody>#{confirm}</tbody></table>").at_css("tr")

      expect(row.at_css("td")["colspan"]).to eq("5")
      expect(row.at_css("p").text).to eq("Delete Signup? Past conversions stay.")
      expect(row.at_css("a")["href"]).to eq("/goals")
    end
  end

  describe "#dash_delta" do
    it "says which way it moved and whether that is good, in words a screen reader hears" do
      delta = html(helper.dash_delta(text: "12%", tone: :bad, direction: :down, title: "vs 40")).at_css("span")

      expect(delta.text.squish).to eq("down 12%, worse")
      expect(delta["title"]).to eq("vs 40")
      expect(delta.at_css("svg|svg", "svg" => "http://www.w3.org/2000/svg")["aria-hidden"]).to eq("true")
    end

    it "carries no direction when there was nothing before" do
      expect(html(helper.dash_delta(text: "New", tone: :new)).text).to eq("New")
    end
  end

  describe "#dash_tile" do
    it "is a link that marks the measure showing, a button that says whether it is pressed, or a plain figure" do
      link = html(helper.dash_tile("Clicks", "1.1k", url: "/clicks", current: true)).at_css("a")
      button = html(helper.dash_tile("Visitors", "883", button: true, current: false, name: "metric", value: "visitors"))
               .at_css("button")
      figure = html(helper.dash_tile("Rules", nil, note: "3 on"))

      expect([ link["href"], link["aria-current"] ]).to eq([ "/clicks", "true" ])
      expect(link.css("span").map(&:text)).to eq([ "Clicks", "1.1k" ])
      expect([ button["type"], button["name"], button["value"], button["aria-pressed"] ]).to eq(%w[submit metric visitors false])
      expect(figure.at_css("a, button")).to be_nil
      expect(figure.text).to include("Rules", "None", "3 on")
    end
  end

  describe "#dash_tiles" do
    it "names the group, and lets a nav name itself" do
      group = html(helper.dash_tiles(label: "Summary figures") { "" }).at_css("div")
      nav = html(helper.dash_tiles(label: "Which measure", element: :nav) { "" }).at_css("nav")

      expect([ group["role"], group["aria-label"] ]).to eq([ "group", "Summary figures" ])
      expect([ nav["role"], nav["aria-label"] ]).to eq([ nil, "Which measure" ])
    end
  end

  describe "#dash_search_field" do
    it "is a search box with a label only a screen reader hears" do
      markup = html(helper.dash_search_field(:q, "botnet", id: "sc-filter", label: "Filter the rows", placeholder: "Filter"))
      input = markup.at_css("input#sc-filter")

      expect(markup.at_css("label[for=sc-filter]").text).to eq("Filter the rows")
      expect([ input["type"], input["name"], input["value"], input["autocomplete"] ]).to eq(%w[search q botnet off])
    end
  end

  describe "#dash_segmented" do
    it "is a named row of links with the current one marked" do
      nav = html(helper.dash_segmented([ { label: "Keywords", url: "/keywords", current: true },
                                         { label: "Sites", url: "/sites", data: { tm_frame: "_top" } } ],
                                       label: "Rank tracking")).at_css("nav")

      expect(nav["aria-label"]).to eq("Rank tracking")
      expect(nav.css("a").map { |link| [ link.text, link["href"], link["aria-current"] ] })
        .to eq([ [ "Keywords", "/keywords", "page" ], [ "Sites", "/sites", nil ] ])
      expect(nav.css("a").last["data-tm-frame"]).to eq("_top")
    end
  end

  describe "#dash_page_tabs" do
    it "puts the tabs on their own row under the head, with any action pushed to the end" do
      row = html(helper.dash_page_tabs(helper.dash_segmented([ { label: "Keywords", url: "/keywords", current: true } ],
                                                             label: "Rank tracking"),
                                       actions: helper.dash_button("Check all", "/check")))

      expect(row.at_css("nav")["aria-label"]).to eq("Rank tracking")
      expect(row.at_css(".page-tabs-actions a")["href"]).to eq("/check")
    end

    it "takes the tabs from a block and leaves out an action it is not given" do
      row = html(helper.dash_page_tabs { helper.dash_segmented([ { label: "Sites", url: "/sites" } ], label: "Sites") })

      expect(row.at_css("nav a").text).to eq("Sites")
      expect(row.at_css(".page-tabs-actions")).to be_nil
    end
  end

  describe "#dash_link" do
    it "goes where it says" do
      link = html(helper.dash_link("Add site", "/sites/new")).at_css("a")

      expect([ link.text, link["href"] ]).to eq([ "Add site", "/sites/new" ])
    end
  end

  describe "#dash_menu" do
    it "wires a toggle to the panel it opens, with whatever sits beside the panel outside it" do
      markup = html(helper.dash_menu(id: "tm-period", label: "Last 7 days", icon: :cal, after: "<p id=dialogs></p>".html_safe,
                                     data: { tm_picker: "period" }) { "Items" })
      menu = markup.at_css("[data-controller='dash--menu']")
      button = menu.at_css("button#tm-period-button")
      panel = menu.at_css("#tm-period")

      expect(menu["data-tm-picker"]).to eq("period")
      expect([ button["type"], button["aria-expanded"], button["aria-controls"], button["data-action"] ])
        .to eq(%w[button false tm-period dash--menu#toggle])
      expect(button.text.strip).to eq("Last 7 days")
      expect(button["aria-pressed"]).to be_nil
      expect([ panel["aria-labelledby"], panel["data-dash--menu-target"], panel.text ])
        .to eq(%w[tm-period-button panel Items])
      expect(menu.at_css("#dialogs").parent).to eq(menu)
    end

    it "says whether a tab toggle holds the view showing, and takes a name of its own" do
      button = html(helper.dash_menu(id: "tm-views", label: "More", toggle: :tab, pressed: false,
                                     aria_label: "More views for pages") { "" }).at_css("button")

      expect([ button["id"], button["aria-pressed"], button["aria-label"] ]).to eq([ "tm-views-button", "false", "More views for pages" ])
    end
  end

  describe "#dash_link_menu" do
    it "lists its links under the heading, with the current one marked" do
      panel = html(helper.dash_link_menu(id: "tm-group", label: "Day", section: "Group by",
                                         items: [ { label: "Day", url: "/?by=day", active: true },
                                                  { label: "Week", url: "/?by=week", note: "7", data: { tm_frame: "_top" } } ]))
              .at_css("#tm-group")

      expect(panel.text).to include("Group by")
      expect(panel.css("a").map { |link| [ link.text.squish, link["href"], link["aria-current"] ] })
        .to eq([ [ "Day", "/?by=day", "true" ], [ "Week 7", "/?by=week", nil ] ])
      expect(panel.css("a").last["data-tm-frame"]).to eq("_top")
    end
  end

  describe "#dash_link_menu with groups" do
    it "puts each group under its own heading, in a labelled group, with a rule between them" do
      panel = html(helper.dash_link_menu(id: "tm-dimension", label: "Page", section: "Break down by",
                                         groups: [ [ "Page", [ { label: "Page", url: "/?d=page", active: true } ] ],
                                                   [ "Source", [ { label: "Source", url: "/?d=source" },
                                                                 { label: "Referrer", url: "/?d=referrer" } ] ] ]))
              .at_css("#tm-dimension")
      groups = panel.css("[role=group]")

      expect(groups.map { |group| panel.at_css("##{group['aria-labelledby']}").text }).to eq(%w[Page Source])
      expect(groups.map { |group| group.css("a").map { |link| [ link.text.squish, link["href"] ] } })
        .to eq([ [ [ "Page", "/?d=page" ] ], [ [ "Source", "/?d=source" ], [ "Referrer", "/?d=referrer" ] ] ])
      expect(panel.css("hr").size).to eq(1)
      expect(panel.at_css("a[aria-current=true]").text.squish).to eq("Page")
      expect(html(helper.dash_link_menu(id: "tm-dimension", label: "Page", section: "Break down by", groups: [ [ "Page", [] ] ]))
        .at_css("button")["aria-label"]).to eq("Break down by: Page")
    end
  end

  describe "#dash_menu_group" do
    it "labels the group by its heading and only rules off a group that follows another" do
      first = html(helper.dash_menu_group("Page", id: "g-0", first: true) { helper.tag.a("Page", href: "/") })
      later = html(helper.dash_menu_group("Source", id: "g-1") { helper.tag.a("Source", href: "/") })

      expect(first.at_css("hr")).to be_nil
      expect(first.at_css("[role=group]")["aria-labelledby"]).to eq("g-0")
      expect(first.at_css("#g-0").text).to eq("Page")
      expect(later.at_css("hr")).to be_present
      expect(later.at_css("[role=group] a").text).to eq("Source")
    end
  end

  describe "#dash_menu_item" do
    it "is a link when it goes somewhere and a button carrying its hooks when it does not" do
      link = html(helper.dash_menu_item("Blog", "/blog", current: true)).at_css("a")
      button = html(helper.dash_menu_item("Chrome", note: "12", role: "option", "aria-selected": "false",
                                          data: { value: "Chrome", action: "dash--picker#choose" })).at_css("button")

      expect([ link.text.strip, link["href"], link["aria-current"] ]).to eq([ "Blog", "/blog", "true" ])
      expect(link.at_css("svg|svg", "svg" => "http://www.w3.org/2000/svg")["aria-hidden"]).to eq("true")
      expect([ button["type"], button["role"], button["aria-selected"], button["data-value"], button["data-action"] ])
        .to eq(%w[button option false Chrome dash--picker#choose])
      expect(button.text.squish).to eq("Chrome 12")
    end

    it "keeps a disabled row visible with what it would say, and posts when given a method" do
      disabled = html(helper.dash_menu_item("Reach back a month", meta: "Pick a property first.", disabled: true)).at_css("button")
      form = html(helper.dash_menu_item("Reach back a month", "/backfill", method: :post, title: "Pull one more month")).at_css("form")

      expect(disabled["disabled"]).not_to be_nil
      expect(disabled.text.squish).to eq("Reach back a month Pick a property first.")
      expect([ form["action"], form["method"] ]).to eq(%w[/backfill post])
      expect(form.at_css("button")["title"]).to eq("Pull one more month")
      expect(form.at_css("button").text).to eq("Reach back a month")
    end

    it "takes its label from a block" do
      item = html(helper.dash_menu_item(nil, "/?country=US") { "United States" }).at_css("a")

      expect([ item.text, item["href"] ]).to eq([ "United States", "/?country=US" ])
    end
  end

  describe "#dash_nav_menu" do
    it "is a nav item whose links are menu targets, with the current page marked" do
      item = html(helper.dash_nav_menu(id: "tm-set-group-0", label: "Traffic",
                                       items: [ { label: "Goals", url: "/goals", active: true, data: { tm_frame: "_top" } },
                                                { label: "Funnels", url: "/funnels" } ])).at_css("li")
      toggle = item.at_css("a#tm-set-group-0-button")
      links = item.css("#tm-set-group-0 a")

      expect([ item["data-controller"], toggle["role"], toggle["aria-controls"], toggle.text ])
        .to eq(%w[dash--menu button tm-set-group-0 Traffic])
      expect(links.map { |link| [ link.text, link["href"], link["aria-current"], link["data-dash--menu-target"] ] })
        .to eq([ [ "Goals", "/goals", "page", "item" ], [ "Funnels", "/funnels", nil, "item" ] ])
      expect(links.first["data-tm-frame"]).to eq("_top")
    end
  end

  describe "#dash_disclosure" do
    it "is a details element whose summary says what opening it does, and what closing it does" do
      details = html(helper.dash_disclosure("Show 4 more", less: "Show fewer", bar: true) { "rows" }).at_css("details")

      expect(details["open"]).to be_nil
      expect(details.at_css("summary").css("span").map(&:text)).to eq([ "Show 4 more", "Show fewer" ])
      expect(details.at_css("summary svg|svg", "svg" => "http://www.w3.org/2000/svg")["aria-hidden"]).to eq("true")
      expect(details.text).to include("rows")
    end

    it "can start open" do
      expect(html(helper.dash_disclosure("About this data", open: true) { "" }).at_css("details")["open"]).not_to be_nil
    end
  end

  describe "#dash_card_disclosure" do
    it "puts the card title in the summary, with its hint beside it" do
      details = html(helper.dash_card_disclosure("Setting it up", hint: "One time") { "steps" }).at_css("details")

      expect(details.at_css("summary h2").text).to eq("Setting it up")
      expect(details.at_css("summary").text).to include("One time")
      expect(details.text).to include("steps")
    end
  end

  describe "#dash_pager" do
    it "is a named nav with only the directions that exist" do
      first = html(helper.dash_pager("Page 1 of 3", label: "Pages of rows", following: "/rows?page=2")).at_css("nav")
      middle = html(helper.dash_pager("Page 2 of 3", previous: "/rows?page=1", following: "/rows?page=3")).at_css("nav")

      expect(first["aria-label"]).to eq("Pages of rows")
      expect(first.css("a").map { |link| [ link.text.strip, link["href"] ] }).to eq([ [ "Next", "/rows?page=2" ] ])
      expect(first.text.squish).to eq("Page 1 of 3 Next")
      expect(middle.css("a").map { |link| link.text.strip }).to eq(%w[Previous Next])
    end
  end
end
