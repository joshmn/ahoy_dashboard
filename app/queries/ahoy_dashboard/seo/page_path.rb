module AhoyDashboard
  module Seo
    module PagePath
      def self.sql(column)
        stripped = "split_part(split_part(regexp_replace(#{column}, '^[a-z][a-z0-9+.-]*://[^/?#]+', '', 'i'), '?', 1), '#', 1)"
        trimmed = "regexp_replace(#{stripped}, '/+$', '')"

        Arel.sql(
          "(case when nullif(btrim(#{column}), '') is null then null " \
          "when left(#{trimmed}, 1) = '/' then #{trimmed} else '/' || #{trimmed} end)"
        )
      end
    end
  end
end
