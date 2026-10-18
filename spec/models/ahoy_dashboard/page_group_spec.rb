require "rails_helper"

RSpec.describe AhoyDashboard::PageGroup do
  describe ".match_case_sql" do
    let(:visit) { create(:ahoy_visit) }

    def grouped(*paths)
      ids = paths.map { |path| dash_page_view(visit, path: path).id }

      AhoyDashboard.event.where(id: ids).order(:id)
        .pluck(described_class.match_case_sql(AhoyDashboard::Sql::EVENT_PATH))
    end

    it "is nil without rules, so the caller reads the plain path" do
      expect(described_class.match_case_sql(AhoyDashboard::Sql::EVENT_PATH)).to be_nil
    end

    it "folds a section under a trailing star and leaves everything else as itself" do
      create(:dash_page_group, name: "Blog", patterns: [ "/blog/*" ])

      expect(grouped("/blog/one", "/blog/two", "/about")).to eq([ "Blog", "Blog", "/about" ])
    end

    it "matches a backslash in a prefix rule as the character it is" do
      create(:dash_page_group, name: "Escaped", patterns: [ "/a\\b*" ])

      expect(grouped("/a\\b/one", "/ab/one")).to eq([ "Escaped", "/ab/one" ])
    end

    it "matches percent signs and underscores in a prefix rule literally" do
      create(:dash_page_group, name: "Literal", patterns: [ "/a_b/100%*" ])

      expect(grouped("/a_b/100%/done", "/axb/100percent/done")).to eq([ "Literal", "/axb/100percent/done" ])
    end

    it "sees a rule written after the dimension's expression was first read" do
      dimension = AhoyDashboard::Dimension.find("page_group")
      expect(dimension.sql.to_s).to eq(AhoyDashboard::Sql::EVENT_PATH.to_s)

      create(:dash_page_group, name: "Blog", patterns: [ "/blog/*" ])

      expect(dimension.sql.to_s).to include("'Blog'")
    end
  end
end
