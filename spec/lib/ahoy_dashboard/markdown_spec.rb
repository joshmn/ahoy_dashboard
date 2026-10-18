require "rails_helper"

RSpec.describe AhoyDashboard::Markdown do
  def render(text)
    described_class.to_html(text)
  end

  describe "blocks" do
    it "wraps prose in paragraphs and keeps blank lines apart" do
      expect(render("One.\n\nTwo.")).to eq("<p>One.</p><p>Two.</p>")
    end

    it "keeps a soft wrap inside one paragraph" do
      expect(render("One\ntwo.")).to eq("<p>One<br>two.</p>")
    end

    it "pulls headings down to h3, because h1 belongs to the page" do
      expect(render("# Top")).to eq("<h3>Top</h3>")
      expect(render("### Three")).to eq("<h3>Three</h3>")
      expect(render("#### Four")).to eq("<h4>Four</h4>")
      expect(render("###### Six")).to eq("<h5>Six</h5>")
    end

    it "draws a rule" do
      expect(render("---")).to eq("<hr>")
      expect(render("***")).to eq("<hr>")
    end

    it "does not read a bullet as a rule" do
      expect(render("- a point")).to eq("<ul><li>a point</li></ul>")
    end

    it "draws a blockquote, and reads what is inside it" do
      expect(render("> **note**")).to eq("<blockquote><p><strong>note</strong></p></blockquote>")
    end

    it "draws a fenced code block without reading it as markdown" do
      expect(render("```ruby\na = **1**\n```"))
        .to eq("<pre><code>a = **1**</code></pre>")
    end

    it "escapes html inside a fence rather than dropping it" do
      expect(render("```\n<script>x</script>\n```"))
        .to eq("<pre><code>&lt;script&gt;x&lt;/script&gt;</code></pre>")
    end
  end

  describe "lists" do
    it "draws an unordered list" do
      expect(render("- a\n- b")).to eq("<ul><li>a</li><li>b</li></ul>")
    end

    it "draws an ordered list" do
      expect(render("1. a\n2. b")).to eq("<ol><li>a</li><li>b</li></ol>")
    end

    it "nests by indentation and comes back out again" do
      expect(render("- a\n  - inner\n- b"))
        .to eq("<ul><li>a</li><ul><li>inner</li></ul><li>b</li></ul>")
    end

    it "ends the list when prose resumes" do
      expect(render("- a\n\nAfter.")).to eq("<ul><li>a</li></ul><p>After.</p>")
    end
  end

  describe "tables" do
    it "draws a pipe table with its header" do
      html = render("| Page | Visitors |\n| --- | --- |\n| /a | 12 |")

      expect(html).to eq(
        "<table><thead><tr><th>Page</th><th>Visitors</th></tr></thead>" \
        "<tbody><tr><td>/a</td><td>12</td></tr></tbody></table>"
      )
    end

    it "leaves a line with a pipe in it alone when nothing says it is a table" do
      expect(render("a | b")).to eq("<p>a | b</p>")
    end
  end

  describe "inline" do
    it "reads bold and italic" do
      expect(render("**b** and *i* and __b__ and _i_"))
        .to eq("<p><strong>b</strong> and <em>i</em> and <strong>b</strong> and <em>i</em></p>")
    end

    it "leaves an underscore inside a word alone" do
      expect(render("prop:facility_id and page_view")).to eq("<p>prop:facility_id and page_view</p>")
    end

    it "reads a code span" do
      expect(render("try `rake build` now")).to eq("<p>try <code>rake build</code> now</p>")
    end

    it "does not read markdown inside a code span" do
      expect(render("`a **b** c`")).to eq("<p><code>a **b** c</code></p>")
    end

    it "leaves bare numbers in prose alone next to a code span" do
      expect(render("`x` gave 0 rows and 1 warning"))
        .to eq("<p><code>x</code> gave 0 rows and 1 warning</p>")
    end

    it "escapes html the model wrote" do
      expect(render("a <b>tag</b> & more")).to eq("<p>a &lt;b&gt;tag&lt;/b&gt; &amp; more</p>")
    end
  end

  describe "links" do
    it "reads a relative link, which is the one the prompt asks for" do
      expect(render("open [explore](/telemetry/explore)"))
        .to eq(%(<p>open <a href="/telemetry/explore">explore</a></p>))
    end

    it "reads an http link" do
      expect(render("[docs](https://example.com/a)"))
        .to eq(%(<p><a href="https://example.com/a">docs</a></p>))
    end

    it "leaves a scheme it does not know as plain text" do
      expect(render("[x](javascript:alert(1))")).to eq("<p>[x](javascript:alert(1))</p>")
      expect(render("[m](mailto:a@b.c)")).to eq("<p>[m](mailto:a@b.c)</p>")
    end
  end

  describe "what it does not understand" do
    it "leaves an image as its literal text" do
      expect(render("![alt](/a.png)")).to eq("<p>!<a href=\"/a.png\">alt</a></p>")
    end

    it "survives an unclosed fence without losing the rest" do
      expect(render("```\nstuck")).to eq("<pre><code>stuck</code></pre>")
    end

    it "survives an unbalanced emphasis marker" do
      expect(render("a ** b")).to eq("<p>a ** b</p>")
    end

    it "answers empty for empty" do
      expect(render("")).to eq("")
      expect(render(nil)).to eq("")
    end
  end

  describe "through the sanitizer the helper applies" do
    let(:view) { ActionView::Base.empty.tap { |v| v.extend(AhoyDashboard::DashboardHelper) } }

    it "keeps the tags an answer needs" do
      html = view.dash_markdown("**b** and [a](/x) and `c`\n\n- one")

      expect(html).to include("<strong>b</strong>", %(<a href="/x">a</a>), "<code>c</code>", "<li>one</li>")
    end

    it "drops anything outside the allowlist" do
      expect(view.dash_markdown("<img src=x onerror=1>")).not_to include("<img")
    end
  end
end
