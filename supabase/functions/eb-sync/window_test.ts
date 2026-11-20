import { assertEquals, assertThrows } from "@std/assert";
import {
  addDays,
  isoDay,
  laterDay,
  shorterPeriods,
  syncWindow,
} from "./window.ts";

const START = "2031-03-01";

Deno.test("first sync: longest from the start date of the owner", () => {
  for (const kind of ["bank", "card"] as const) {
    assertEquals(
      syncWindow({
        kind,
        startDate: START,
        firstSync: true,
        lastSuccess: null,
      }),
      { strategy: "longest", dateFrom: START },
    );
  }
});

Deno.test("first sync of PayPal: longest from 90 days before the start date", () => {
  assertEquals(
    syncWindow({
      kind: "paypal",
      startDate: START,
      firstSync: true,
      lastSuccess: null,
    }),
    { strategy: "longest", dateFrom: "2030-12-01" },
  );
});

Deno.test("later syncs: default from the last successful one minus 15 days", () => {
  assertEquals(
    syncWindow({
      kind: "bank",
      startDate: START,
      firstSync: false,
      lastSuccess: "2031-03-20",
    }),
    { strategy: "default", dateFrom: "2031-03-05" },
  );
  assertEquals(
    syncWindow({
      kind: "paypal",
      startDate: START,
      firstSync: false,
      lastSuccess: "2031-06-10",
    }),
    { strategy: "default", dateFrom: "2031-05-26" },
  );
});

Deno.test("later syncs: never before the start date, PayPal too", () => {
  for (const kind of ["bank", "paypal"] as const) {
    assertEquals(
      syncWindow({
        kind,
        startDate: START,
        firstSync: false,
        lastSuccess: "2031-03-10",
      }),
      { strategy: "default", dateFrom: START },
    );
  }
  // Rows without a successful sync: from the start date.
  assertEquals(
    syncWindow({
      kind: "card",
      startDate: START,
      firstSync: false,
      lastSuccess: null,
    }),
    { strategy: "default", dateFrom: START },
  );
});

Deno.test("shorter periods: today minus 89, 60, 30 days, never before the date asked", () => {
  assertEquals(shorterPeriods("2031-01-01", "2031-09-30"), [
    "2031-07-03",
    "2031-08-01",
    "2031-08-31",
  ]);
  // The date asked is more recent than today − 89: only the later ones.
  assertEquals(shorterPeriods("2031-07-15", "2031-09-30"), [
    "2031-08-01",
    "2031-08-31",
  ]);
  // More recent than today − 30: nothing shorter to try.
  assertEquals(shorterPeriods("2031-09-15", "2031-09-30"), []);
});

Deno.test("dates: days across months and years, later of two, UTC day", () => {
  assertEquals(addDays("2031-03-01", -1), "2031-02-28");
  assertEquals(addDays("2032-03-01", -1), "2032-02-29");
  assertEquals(addDays("2031-12-31", 1), "2032-01-01");
  assertEquals(laterDay("2031-03-01", "2031-02-28"), "2031-03-01");
  assertEquals(isoDay(Date.parse("2031-03-20T23:30:00-02:00")), "2031-03-21");
  assertThrows(() => addDays("01/03/2031", 1), RangeError);
});
