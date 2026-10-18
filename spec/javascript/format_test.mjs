import assert from "node:assert/strict"
import test from "node:test"
import { compact, delimited, duration, format, tick } from "../../assets/javascript/runtime/format.js"

const compacted = (values) => values.map((value) => compact(value))

test("compact prints one decimal below a hundred of a unit and none from a hundred up", () => {
  assert.deepEqual(compacted([999, 3000, 3100, 23340, 123400, 1200000]), ["999", "3.0k", "3.1k", "23.3k", "123k", "1.2M"])
})

test("compact rolls over to the next unit rather than printing a thousand of one", () => {
  assert.deepEqual(compacted([999.5, 999.6, 99950, 99960, 999960]), ["1.0k", "1.0k", "100k", "100k", "1.0M"])
})

test("compact rounds a tenth the way the server's format does", () => {
  assert.deepEqual(compacted([1050, 1150, 1250, 1750, 2450, 77550, 1250000]), ["1.0k", "1.2k", "1.2k", "1.8k", "2.4k", "77.6k", "1.2M"])
})

test("compact keeps the sign and never prints a negative zero", () => {
  assert.deepEqual(compacted([-1250, -622.5, -0.4, 0]), ["-1.2k", "-623", "0", "0"])
})

test("compact stops at billions", () => {
  assert.deepEqual(compacted([1e9, 2.5e12]), ["1.0B", "2500B"])
})

test("delimited rounds to a whole number with thousands separators", () => {
  assert.deepEqual([delimited(1234.5), delimited(999), delimited(0)], ["1,235", "999", "0"])
})

test("duration reads as hours and minutes, minutes and seconds, or seconds", () => {
  assert.deepEqual([duration(3725), duration(125), duration(42)], ["1h 2m", "2m 5s", "42s"])
})

test("format prints each metric type", () => {
  assert.deepEqual(
    [
      format(1234.5),
      format(1234.5, "integer"),
      format(0.456, "decimal"),
      format(12.4, "percent"),
      format(12.34, "rate"),
      format(12, "rate"),
      format(125, "duration"),
      format(1234.56, "currency"),
      format("abc")
    ],
    ["1,235", "1,235", "0.46", "12%", "12.3%", "12%", "2m 5s", "$1,235", "0"]
  )
})

test("an integer axis tick compacts with the chart's own rounding, which is not quite the server's", () => {
  assert.deepEqual([tick(0), tick(500), tick(1250), tick(1050), tick(1500)], ["0", "500", "1.3k", "1.1k", "1.5k"])
})

test("a duration tick drops its seconds once it reaches a minute", () => {
  assert.deepEqual([tick(59, "duration"), tick(150, "duration")], ["59s", "3m"])
})

test("decimal and other ticks", () => {
  assert.deepEqual([tick(0.25, "decimal"), tick(12.34, "rate"), tick(12.4, "percent")], ["0.3", "12.3%", "12%"])
})
