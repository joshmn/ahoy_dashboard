module AhoyDashboard
  # Markdown, but only the parts an answer needs.
  #
  # This exists so the gem carries no markdown library. The input is one
  # assistant reply, and the output is fed straight to Rails' sanitizer against
  # a fixed tag allowlist, so anything this does not understand degrades to the
  # literal characters the model typed rather than to markup. That is the whole
  # safety story: a gap here is cosmetic, never structural.
  module Markdown
    def self.to_html(text)
      Renderer.new(text).to_html
    end

    class Renderer
      # h1 and h2 belong to the page, not to something written inside a chat
      # bubble, so everything shallower than h3 is pulled down to it.
      HEADING = /\A(\#{1,6})\s+(.*)\z/
      FENCE = /\A\s*(```|~~~)\s*[\w+-]*\s*\z/
      RULE = /\A\s*([-*_])(?:\s*\1){2,}\s*\z/
      QUOTE = /\A>\s?(.*)\z/
      BULLET = /\A(\s*)[-*+]\s+(.*)\z/
      NUMBER = /\A(\s*)\d+[.)]\s+(.*)\z/
      DIVIDER = /\A\s*\|?[\s:|-]*-[\s:|-]*\|?\s*\z/

      # Anything else, mailto and javascript included, drops back to its text.
      # The sanitizer would take it too; this way the reader sees what the model
      # actually wrote instead of a link that silently lost its href.
      SAFE_HREF = %r{\A(?:https?://|/|\#)}

      def initialize(text)
        @lines = text.to_s.delete("\r").split("\n")
        @out = +""
      end

      def to_html
        blocks(@lines)
        @out
      end

      private

      def blocks(lines)
        index = 0

        while index < lines.length
          line = lines[index]

          index = if line.strip.empty? then index + 1
          elsif line.match?(FENCE) then code(lines, index)
          elsif line.match?(RULE) then rule(index)
          elsif (head = line.match(HEADING)) then heading(head, index)
          elsif line.match?(QUOTE) then quote(lines, index)
          elsif table?(lines, index) then table(lines, index)
          elsif item(line) then list(lines, index)
          else paragraph(lines, index)
          end
        end
      end

      def rule(index)
        @out << "<hr>"
        index + 1
      end

      def heading(match, index)
        level = match[1].length.clamp(3, 5)
        @out << "<h#{level}>#{inline(match[2])}</h#{level}>"
        index + 1
      end

      def code(lines, index)
        fence = lines[index].strip[0, 3]
        body = []
        cursor = index + 1

        while cursor < lines.length && !lines[cursor].strip.start_with?(fence)
          body << lines[cursor]
          cursor += 1
        end

        @out << "<pre><code>#{escape(body.join("\n"))}</code></pre>"
        cursor + 1
      end

      def quote(lines, index)
        body = []
        cursor = index

        while cursor < lines.length && (match = lines[cursor].match(QUOTE))
          body << match[1]
          cursor += 1
        end

        @out << "<blockquote>"
        blocks(body)
        @out << "</blockquote>"
        cursor
      end

      # Indentation opens a nested list and closing it returns to the outer one.
      # A model produces those constantly, and a flat parser renders them as a
      # run of same-level items that reads as a different answer.
      def list(lines, index)
        ordered = lines[index].match?(NUMBER)
        indent = item(lines[index]).first.length
        cursor = index

        @out << (ordered ? "<ol>" : "<ul>")

        while cursor < lines.length && (parts = item(lines[cursor]))
          break if parts.first.length < indent

          if parts.first.length > indent
            cursor = list(lines, cursor)
            next
          end

          @out << "<li>#{inline(parts.last)}</li>"
          cursor += 1
        end

        @out << (ordered ? "</ol>" : "</ul>")
        cursor
      end

      def item(line)
        match = line&.match(BULLET) || line&.match(NUMBER)
        return nil if match.nil?

        [ match[1], match[2] ]
      end

      def table?(lines, index)
        return false unless lines[index].include?("|")

        below = lines[index + 1].to_s

        below.include?("-") && below.match?(DIVIDER)
      end

      def table(lines, index)
        head = cells(lines[index])
        cursor = index + 2
        rows = []

        while cursor < lines.length && lines[cursor].include?("|")
          rows << cells(lines[cursor])
          cursor += 1
        end

        @out << "<table><thead><tr>"
        head.each { |cell| @out << "<th>#{inline(cell)}</th>" }
        @out << "</tr></thead><tbody>"
        rows.each do |row|
          @out << "<tr>"
          row.each { |cell| @out << "<td>#{inline(cell)}</td>" }
          @out << "</tr>"
        end
        @out << "</tbody></table>"

        cursor
      end

      def cells(line)
        line.strip.delete_prefix("|").delete_suffix("|").split("|").map(&:strip)
      end

      def paragraph(lines, index)
        body = []
        cursor = index

        while cursor < lines.length && !lines[cursor].strip.empty? && !structural?(lines, cursor)
          body << lines[cursor]
          cursor += 1
        end

        @out << "<p>#{inline(body.join("\n"))}</p>"
        cursor
      end

      def structural?(lines, index)
        line = lines[index]

        line.match?(HEADING) || line.match?(FENCE) || line.match?(RULE) ||
          line.match?(QUOTE) || !item(line).nil? || table?(lines, index)
      end

      SPAN = /(`[^`]+`)/

      # The text is cut around its code spans and only the pieces between them
      # are read for emphasis and links. Split rather than substitute a
      # placeholder: every placeholder that reads as ordinary text is a
      # collision waiting for the answer that happens to contain it.
      def inline(text)
        text.to_s.split(SPAN).map do |part|
          if part.match?(/\A`[^`]+`\z/)
            "<code>#{escape(part[1..-2])}</code>"
          else
            emphasis(links(escape(part)))
          end
        end.join
      end

      def emphasis(text)
        text
          .gsub(/\*\*(.+?)\*\*/m, "<strong>\\1</strong>")
          .gsub(/__(.+?)__/m, "<strong>\\1</strong>")
          .gsub(/(?<![\w*])\*(?!\s)([^*]+?)(?<!\s)\*(?![\w*])/m, "<em>\\1</em>")
          .gsub(/(?<![\w_])_(?!\s)([^_]+?)(?<!\s)_(?![\w_])/m, "<em>\\1</em>")
          .gsub("\n", "<br>")
      end

      def links(text)
        text.gsub(/\[([^\]]*)\]\(([^)\s]+)\)/) do
          label = Regexp.last_match(1)
          href = Regexp.last_match(2)

          href.match?(SAFE_HREF) ? %(<a href="#{href}">#{label}</a>) : "[#{label}](#{href})"
        end
      end

      def escape(text)
        text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      end
    end
  end
end
