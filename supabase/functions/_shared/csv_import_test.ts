import {
  assertEquals,
  assert,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  parseCsvTransactions,
  parseChaseCsv,
  normalizeCategory,
  mapChaseCategory,
  normalizeType,
  csvTransactionId,
  legacyCsvTransactionId,
  normalizeDate,
  buildTransactionRecord,
  type CsvRow,
} from "./csv_import.ts";
import { normalizeMerchant } from "./reconcile.ts";

const CHASE_CSV = `Transaction Date,Post Date,Description,Category,Type,Amount,Memo
10/08/2026,10/11/2026,TST*WUSONG ROAD - CAMBRI,Food & Drink,Sale,-91.08,
10/02/2026,10/04/2026,DD *DOORDASH DOMINOS,Food & Drink,Sale,-106.13,
09/29/2026,09/30/2026,Payment Thank You-Mobile,,Payment,6119.99,
09/26/2026,09/27/2026,MBTA-550047114842,Travel,Sale,-2.40,`;

// Capital One style: charges positive, payments negative, Debit/Credit columns
const CAPITAL_ONE_CSV = `Transaction Date,Description,Debit,Credit,Category
01/15/2026,Starbucks Coffee,3.45,,Food & Drink
01/14/2026,Payment Thank You,,6000.00,Payment`;

// Amex style: positive charges, Date/Description/Amount columns
const AMEX_CSV = `Date,Description,Amount,Currency
2026-01-15,STARBUCKS COFFEE,3.45,USD
2026-01-14,PAYMENT THANK YOU,-6000.00,USD`;

// European: semicolon delimiter, decimal comma, charges positive
const EUROPEAN_CSV = `Date;Description;Amount;Category
15/01/2026;Café Central;3,45;Food`;

// File with unparseable date
const BAD_DATE_CSV = `Date,Description,Amount
NOTADATE,Starbucks Coffee,3.45`;

// File with total/balance row (should be skipped)
const WITH_TOTALS_CSV = `Date,Description,Amount
2026-01-15,Starbucks Coffee,3.45
TOTAL,,100.00`;

// File with last-4 in description
const WITH_LAST4_CSV = `Transaction Date,Post Date,Description,Category,Type,Amount
10/08/2026,10/11/2026,TST*WUSONG ROAD - CAMBRI*1234,Food & Drink,Sale,-91.08,
10/02/2026,10/04/2026,ANOTHER PURCHASE ending in 1234,Food & Drink,Sale,-10.00,`;

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

/* -------------------------------------------------------------------------- */
/* Chase CSV: sign detection, category mapping, and output                    */
/* -------------------------------------------------------------------------- */

Deno.test("Chase CSV: charges normalized to positive, payments to negative", () => {
  const result = parseCsvTransactions(CHASE_CSV);

  assertEquals(result.rows.length, 4);
  assertEquals(result.chargeSign, "negative");
  assertEquals(result.signFlipped, true);

  // Charge rows should be positive
  const chargeRows = result.rows.filter(r => r.amount > 0);
  assertEquals(chargeRows.length, 3);

  // Payment row should be negative
  const paymentRows = result.rows.filter(r => r.amount < 0);
  assertEquals(paymentRows.length, 1);
  assertEquals(round2(paymentRows[0].amount), -6119.99);
});

Deno.test("Chase CSV: parseChaseCsv is an alias for parseCsvTransactions", () => {
  const a = parseCsvTransactions(CHASE_CSV);
  const b = parseChaseCsv(CHASE_CSV);
  assertEquals(a.rows.length, b.rows.length);
  assertEquals(a.chargeSign, b.chargeSign);
  assertEquals(a.signFlipped, b.signFlipped);
});

Deno.test("Chase CSV: category normalization", () => {
  const result = parseCsvTransactions(CHASE_CSV);
  const byMerchant = new Map(result.rows.map(r => [r.description, r]));

  assertEquals(byMerchant.get("TST*WUSONG ROAD - CAMBRI")?.category, "FOOD_AND_DRINK");
  assertEquals(byMerchant.get("DD *DOORDASH DOMINOS")?.category, "FOOD_AND_DRINK");
  assertEquals(byMerchant.get("MBTA-550047114842")?.category, "TRAVEL");
  assertEquals(byMerchant.get("Payment Thank You-Mobile")?.category, "");
});

Deno.test("Chase CSV: type normalization", () => {
  const result = parseCsvTransactions(CHASE_CSV);
  const chargeTypes = result.rows.filter(r => r.amount > 0).map(r => normalizeType(r.type, r.amount));
  const paymentTypes = result.rows.filter(r => r.amount < 0).map(r => normalizeType(r.type, r.amount));

  chargeTypes.forEach(t => assertEquals(t, "purchase"));
  paymentTypes.forEach(t => assertEquals(t, "payment"));
});

/* -------------------------------------------------------------------------- */
/* Sign auto-detection                                                        */
/* -------------------------------------------------------------------------- */

Deno.test("Capital One CSV: Debit/Credit columns, positive charges, no file-level flip", () => {
  const result = parseCsvTransactions(CAPITAL_ONE_CSV);
  assertEquals(result.rows.length, 2);

  const charge = result.rows.find(r => r.description.includes("Starbucks"));
  const payment = result.rows.find(r => r.description.includes("Payment"));
  assert(charge && charge.amount > 0, "Charge should be positive");
  assert(payment && payment.amount < 0, "Payment should be negative");
  assertEquals(result.signFlipped, false);
});

Deno.test("Amex CSV: positive charges, chargeSign=positive", () => {
  const result = parseCsvTransactions(AMEX_CSV);
  assertEquals(result.rows.length, 2);
  assertEquals(result.chargeSign, "positive");
  assertEquals(result.signFlipped, false);

  const charge = result.rows.find(r => r.description.includes("STARBUCKS"));
  const payment = result.rows.find(r => r.description.includes("PAYMENT"));
  assert(charge && charge.amount > 0);
  assert(payment && payment.amount < 0);
});

/* -------------------------------------------------------------------------- */
/* Date parsing                                                               */
/* -------------------------------------------------------------------------- */

Deno.test("normalizeDate: handles various formats", () => {
  assertEquals(normalizeDate("2026-01-15"), "2026-01-15");
  assertEquals(normalizeDate("2026/01/15"), "2026-01-15");
  assertEquals(normalizeDate("01/15/2026"), "2026-01-15");
  assertEquals(normalizeDate("15/01/2026"), "2026-01-15"); // day > 12 = DD/MM
});

Deno.test("normalizeDate: ambiguous MM/DD defaults to US", () => {
  assertEquals(normalizeDate("05/03/2026"), "2026-05-03");
});

Deno.test("Bad date is preserved but not normalized", () => {
  // parseDateCell returns null for unparseable, normalizeDate falls back to raw
  assertEquals(normalizeDate("NOTADATE"), "NOTADATE");
});

/* -------------------------------------------------------------------------- */
/* Row filtering                                                              */
/* -------------------------------------------------------------------------- */

Deno.test("Total/balance rows are skipped", () => {
  const result = parseCsvTransactions(WITH_TOTALS_CSV);
  assertEquals(result.rows.length, 1);
  assertEquals(result.rows[0].description, "Starbucks Coffee");
});

Deno.test("Empty description rows are skipped", () => {
  const csv = `Date,Description,Amount
2026-01-15,,3.45
2026-01-16,Starbucks,5.00`;
  const result = parseCsvTransactions(csv);
  assertEquals(result.rows.length, 1);
  assertEquals(result.rows[0].description, "Starbucks");
});

/* -------------------------------------------------------------------------- */
/* Currency detection                                                         */
/* -------------------------------------------------------------------------- */

Deno.test("Multi-currency column detection", () => {
  const csv = `Date,Description,Amount,Currency
2026-01-15,Café Central,3.45,EUR
2026-01-14,Payment,-60.00,EUR`;
  const result = parseCsvTransactions(csv);
  assertEquals(result.detectedCurrency, "EUR");
  assertEquals(result.rows[0].currency, "EUR");
});

Deno.test("Currency from options parameter", () => {
  const csv = `Date,Description,Amount
2026-01-15,Starbucks Coffee,3.45`;
  const result = parseCsvTransactions(csv, { currency: "GBP" });
  assertEquals(result.rows[0].currency, "GBP");
});

Deno.test("Currency defaults to USD", () => {
  const result = parseCsvTransactions(AMEX_CSV);
  assertEquals(result.rows[0].currency, "USD");
});

/* -------------------------------------------------------------------------- */
/* Category mapping (universal)                                               */
/* -------------------------------------------------------------------------- */

Deno.test("normalizeCategory: maps common bank categories to Plaid values", () => {
  assertEquals(normalizeCategory("Food & Drink"), "FOOD_AND_DRINK");
  assertEquals(normalizeCategory("Restaurants"), "FOOD_AND_DRINK");
  assertEquals(normalizeCategory("Coffee Shop"), "FOOD_AND_DRINK");
  assertEquals(normalizeCategory("Groceries"), "FOOD_AND_DRINK");
  assertEquals(normalizeCategory("Travel"), "TRAVEL");
  assertEquals(normalizeCategory("Airline"), "TRAVEL");
  assertEquals(normalizeCategory("Gas"), "TRANSPORTATION");
  assertEquals(normalizeCategory("Shopping"), "GENERAL_MERCHANDISE");
  assertEquals(normalizeCategory("Entertainment"), "ENTERTAINMENT");
  assertEquals(normalizeCategory("Health & Wellness"), "MEDICAL");
  assertEquals(normalizeCategory("Bills & Utilities"), "RENT_AND_UTILITIES");
  assertEquals(normalizeCategory("Income"), "INCOME");
  assertEquals(normalizeCategory("Transfer"), "TRANSFER");
});

Deno.test("normalizeCategory: falls back to raw for unrecognized", () => {
  assertEquals(normalizeCategory("Custom Category"), "Custom Category");
  assertEquals(normalizeCategory(""), "");
});

Deno.test("mapChaseCategory is an alias for normalizeCategory", () => {
  assertEquals(mapChaseCategory("Food & Drink"), normalizeCategory("Food & Drink"));
  assertEquals(mapChaseCategory("Gas"), normalizeCategory("Gas"));
});

/* -------------------------------------------------------------------------- */
/* Type normalization (generalized)                                           */
/* -------------------------------------------------------------------------- */

Deno.test("normalizeType: maps known types", () => {
  assertEquals(normalizeType("Sale"), "purchase");
  assertEquals(normalizeType("purchase"), "purchase");
  assertEquals(normalizeType("Payment"), "payment");
  assertEquals(normalizeType("Credit"), "payment");
  assertEquals(normalizeType("Return"), "return");
  assertEquals(normalizeType("Refund"), "return");
  assertEquals(normalizeType("Adjustment"), "adjustment");
  assertEquals(normalizeType("Transfer"), "transfer");
});

Deno.test("normalizeType: falls back to amount sign for unrecognized types", () => {
  assertEquals(normalizeType("SomethingUnknown", 50.0), "purchase");
  assertEquals(normalizeType("SomethingUnknown", -50.0), "payment");
  assertEquals(normalizeType("SomethingUnknown"), "purchase"); // default when no amount
});

/* -------------------------------------------------------------------------- */
/* Last-4 extraction                                                          */
/* -------------------------------------------------------------------------- */

Deno.test("extractLast4: various card number formats", () => {
  const csv = `Transaction Date,Post Date,Description,Category,Type,Amount
10/08/2026,10/11/2026,TST*WUSONG ROAD - CAMBRI*1234,Food & Drink,Sale,-91.08,
10/02/2026,10/04/2026,ANOTHER PURCHASE ending in 1234,Food & Drink,Sale,-10.00,`;
  const result = parseCsvTransactions(csv);
  assertEquals(result.detectedCardLast4, "1234");
});

/* -------------------------------------------------------------------------- */
/* Transaction ID backward compatibility                                      */
/* -------------------------------------------------------------------------- */

Deno.test("csvTransactionId uses absolute cents (sign-agnostic)", async () => {
  const rowA: CsvRow = { ...minimalRow(), amount: 50 };
  const rowB: CsvRow = { ...minimalRow(), amount: -50 };
  const idA = await csvTransactionId("acct1", rowA);
  const idB = await csvTransactionId("acct1", rowB);
  assertEquals(idA, idB, "Same magnitude should produce same ID regardless of sign");
});

Deno.test("legacyCsvTransactionId produces different ID for non-zero signed amounts", async () => {
  const row: CsvRow = { ...minimalRow(), amount: 50 };
  const newId = await csvTransactionId("acct1", row);
  const legacyId = await legacyCsvTransactionId("acct1", row);
  assert(newId !== legacyId, "New and legacy IDs should differ for non-zero amounts");
});

Deno.test("legacyCsvTransactionId reproduces old Chase ID for charges", async () => {
  // Old code used Math.round(row.amount * 100) where row.amount was the RAW amount.
  // For Chase, raw charge = -91.08 → old ID key had -9108.
  // New parser normalizes to +91.08. Legacy ID negates → -9108. Should match.
  const chaseChargeRow: CsvRow = { ...minimalRow(), amount: 91.08 }; // normalized (was -91.08)
  const legacyId = await legacyCsvTransactionId("acct1", chaseChargeRow);
  // Manually compute what old ID would have been (using raw -91.08)
  const oldKey = ["acct1", normalizeDate("10/17/2026"), normalizeDate("01/10/2026"), Math.round(-91.08 * 100), normalizeMerchant("Starbucks"), normalizeType("Sale")].join("|");
  const oldHash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(oldKey));
  const oldId = "csv_" + Array.from(new Uint8Array(oldHash)).map(b => b.toString(16).padStart(2, "0")).join("").slice(0, 32);
  assertEquals(legacyId, oldId, "Legacy ID should match old Chase ID format");
});

function minimalRow(): CsvRow {
  return {
    transactionDate: "01/10/2026",
    postDate: "10/17/2026",
    description: "Starbucks",
    category: "Food & Drink",
    type: "Sale",
    amount: 50,
    currency: "USD",
    memo: "",
  };
}

/* -------------------------------------------------------------------------- */
/* buildTransactionRecord                                                     */
/* -------------------------------------------------------------------------- */

Deno.test("buildTransactionRecord stores normalized amount (no double negation)", () => {
  const row: CsvRow = {
    transactionDate: "01/15/2026",
    postDate: "01/17/2026",
    description: "Starbucks Coffee",
    category: "Food & Drink",
    type: "sale",
    amount: 91.08,
    currency: "USD",
    memo: "",
  };

  const record = buildTransactionRecord("acct1", "user1", row, "USD");
  assertEquals(record.amount, 91.08, "Should store the amount as-is (already normalized)");
  assertEquals(record.iso_currency_code, "USD");
  assertEquals(record.source, "csv_import");
  assertEquals(record.pending, false);
  assertEquals(record.is_removed, false);
});

/* -------------------------------------------------------------------------- */
/* Column detection robustness                                                */
/* -------------------------------------------------------------------------- */

Deno.test("Non-Chase headers with synonyms are detected", () => {
  const csv = `Date,Merchant,Amount,Category
2026-01-15,Starbucks Coffee,3.45,Food`;
  const result = parseCsvTransactions(csv);
  assertEquals(result.rows.length, 1);
  assertEquals(result.rows[0].description, "Starbucks Coffee");
  assertEquals(round2(result.rows[0].amount), 3.45);
});

Deno.test("Missing required columns throws descriptive error", () => {
  const csv = `JustOneColumn,AnotherColumn
data1,data2`;
  assertThrows(
    () => parseCsvTransactions(csv),
    Error,
    "Could not detect",
  );
});

Deno.test("Multiple date columns are assigned correctly (trans vs post)", () => {
  const csv = `Transaction Date,Post Date,Description,Amount
01/10/2026,01/12/2026,Starbucks,3.45
01/10/2026,01/12/2026,Payment,-6000.00`;
  const result = parseCsvTransactions(csv);
  assertEquals(result.rows.length, 2);
  assertEquals(result.rows[0].transactionDate, "01/10/2026");
  assertEquals(result.rows[0].postDate, "01/12/2026");
});

Deno.test("European format: semicolon delimiter and decimal comma", () => {
  const result = parseCsvTransactions(EUROPEAN_CSV);
  assertEquals(result.rows.length, 1);
  assertEquals(round2(result.rows[0].amount), 3.45);
});

Deno.test("Quoted fields with embedded commas and newlines", () => {
  const csv = `Date,Description,Amount
01/15/2026,"Starbucks, Coffee",3.45
01/16/2026,"Multi,
line description",5.00`;
  const result = parseCsvTransactions(csv);
  assertEquals(result.rows.length, 2);
  assertEquals(result.rows[0].description, "Starbucks, Coffee");
  assertEquals(result.rows[1].description, "Multi,\nline description");
});
