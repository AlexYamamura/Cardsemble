import { supabase } from "./supabase.ts";
import { normalizeMerchant } from "./reconcile.ts";

export interface CsvRow {
  transactionDate: string;
  postDate: string;
  description: string;
  category: string;
  type: string;
  amount: number;
  currency: string;
  memo: string;
}

export interface ParsedCsv {
  rows: CsvRow[];
  detectedCardName?: string;
  detectedCardLast4?: string;
  /** Currency detected from the data or options; undefined if default "USD" */
  detectedCurrency?: string;
  /** Which sign in the raw CSV represents a charge (purchase) */
  chargeSign?: "positive" | "negative";
  /** True if amounts were flipped to reach Plaid convention (positive=charge) */
  signFlipped?: boolean;
  /** Resolved column indexes for debugging/validation */
  detectedColumns?: ColumnMap;
}

export interface PreviewRow {
  row: CsvRow;
  status: "new" | "duplicate" | "error";
  match?: Record<string, unknown>;
  matchScore?: number;
  error?: string;
  /** If present, indicates this is a duplicate within the same CSV import */
  duplicateReason?: "intra_csv";
}

export interface CsvPreviewResult {
  preview: PreviewRow[];
  summary: { new: number; duplicate: number; error: number };
  accountValidation?: { matched: boolean; warning?: string };
  /** Surface detected metadata to the UI for debugging */
  detectedCurrency?: string;
  chargeSign?: "positive" | "negative";
  signFlipped?: boolean;
}

/**
 * Alias kept for backward compatibility. The internal callers have been
 * updated to use `parseCsvTransactions`, but external code may still
 * reference `parseChaseCsv`.
 */
export { parseCsvTransactions as parseChaseCsv };

/* -------------------------------------------------------------------------- */
/* CSV parsing (state machine)                                                 */
/* -------------------------------------------------------------------------- */

/**
 * Parse CSV text into a 2-D array of strings.
 *
 * Fixes the original line-by-line parser which reset `inQuotes` at every
 * newline, making it unable to handle quoted fields that contain embedded
 * newlines (a common occurrence in multi-line descriptions).
 */
function parseCsv(text: string, delimiter: string = ","): string[][] {
  // Strip UTF-8 BOM if present
  if (text.charCodeAt(0) === 0xFEFF) {
    text = text.slice(1);
  }

  const result: string[][] = [];
  let current: string[] = [];
  let inQuotes = false;
  let cell = "";

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === '"') {
      if (inQuotes && text[i + 1] === '"') {
        cell += '"';
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch === delimiter && !inQuotes) {
      current.push(cell);
      cell = "";
    } else if (ch === "\n" && !inQuotes) {
      current.push(cell);
      if (current.length > 1 || current[0]) {
        result.push(current);
      }
      current = [];
      cell = "";
    } else if (ch === "\r") {
      // Treat \r\n and standalone \r as line separators
      if (i + 1 < text.length && text[i + 1] !== "\n") {
        current.push(cell);
        if (current.length > 1 || current[0]) {
          result.push(current);
        }
        current = [];
        cell = "";
      }
      // If \r is followed by \n, the \n handler will finalize the row
    } else {
      cell += ch;
    }
  }

  // Flush the last cell/row
  if (cell || current.length > 0) {
    current.push(cell);
    if (current.length > 1 || current[0]) {
      result.push(current);
    }
  }

  return result;
}

/**
 * Sniff the delimiter from a CSV text sample by counting candidate
 * delimiters that appear outside of quoted regions.
 */
function sniffDelimiter(text: string): string {
  const sample = text.slice(0, Math.min(8192, text.length));
  const candidates = [",", ";", "\t", "|"];
  const counts: Record<string, number> = {};

  for (const delim of candidates) {
    let count = 0;
    let inQuotes = false;
    for (const ch of sample) {
      if (ch === '"') {
        inQuotes = !inQuotes;
      } else if (ch === delim && !inQuotes) {
        count++;
      }
    }
    counts[delim] = count;
  }

  let best = candidates[0];
  let bestCount = counts[best];
  for (let i = 1; i < candidates.length; i++) {
    if (counts[candidates[i]] > bestCount) {
      best = candidates[i];
      bestCount = counts[candidates[i]];
    }
  }

  return bestCount > 0 ? best : ",";
}

/* -------------------------------------------------------------------------- */
/* Column detection                                                            */
/* -------------------------------------------------------------------------- */

/**
 * Canonical field key → list of header aliases (normalized form).
 * Normalization: lowercase, strip non-alphanumerics, collapse spaces.
 */
const HEADER_ALIASES: Record<string, string[]> = {
  transactionDate: [
    "transaction date", "trans date", "trans dt", "transaction_dt", "date",
    "purchase date", "activity date", "transaction date ",
  ],
  postDate: [
    "post date", "posted date", "posting date", "settlement date",
    "settle date", "processing date",
  ],
  description: [
    "description", "merchant", "merchant name", "name", "payee",
    "details", "transaction description", "transaction details",
    "description amount", "merchantdescription",
  ],
  category: ["category", "category name", "cat", "merchant category"],
  type: [
    "type", "transaction type", "debit/credit", "dr/cr", "charge type",
    "debitcredit", "trans type",
  ],
  amount: [
    "amount", "transaction amount", "amt", "value", "amount usd",
    "dollar amount", "price", "sum",
  ],
  debit: ["debit", "withdrawal", "withdrawals", "dr", "charge", "charges"],
  credit: ["credit", "deposit", "deposits", "cr", "payment", "payments"],
  memo: ["memo", "notes", "note", "comment", "additional info", "detail"],
  currency: [
    "currency", "ccy", "currency code", "iso currency", "iso currency code",
  ],
};

/** Normalize a header string for alias comparison. */
function normalizeHeader(h: string): string {
  return h
    .replace(/^\uFEFF/, "")  // strip BOM if still present at cell level
    .toLowerCase()
    .replace(/[^a-z0-9]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

interface ColumnMap {
  transactionDate?: number;
  postDate?: number;
  description?: number;
  category?: number;
  type?: number;
  amount?: number;
  debit?: number;
  credit?: number;
  memo?: number;
  currency?: number;
}

/**
 * Headers that look like dates but should be denied for the transaction-date
 * or post-date columns (e.g., "Payment Due Date", "Statement Date").
 */
const DENYLIST_DATE_PATTERNS = [
  /due date/i, /statement date/i, /statement due/i, /closing date/i,
  /billing date/i, /payment date/i, /credit limit/i, /balance transfer /i,
];

/** Check if a header name matches any alias for the given canonical field. */
function headerMatchesAlias(headerNorm: string, fieldKey: string): boolean {
  const aliases = HEADER_ALIASES[fieldKey] || [];
  for (const alias of aliases) {
    const aliasNorm = normalizeHeader(alias);
    if (headerNorm === aliasNorm) return true;
  }
  return false;
}

/** Scan the first N rows to find the header row by scoring alias matches. */
function findHeaderRow(rows: string[][], maxScan = 10): number {
  let bestIdx = -1;
  let bestScore = 0;

  for (let i = 0; i < Math.min(maxScan, rows.length); i++) {
    const row = rows[i];
    if (!row) break;
    let score = 0;
    const assigned = new Set<number>();
    for (let col = 0; col < row.length; col++) {
      const headerNorm = normalizeHeader(row[col] || "");
      if (headerNorm.length < 3) continue;
      for (const fieldKey of Object.keys(HEADER_ALIASES)) {
        if (assigned.has(col)) break;
        if (headerMatchesAlias(headerNorm, fieldKey)) {
          score += 2;
          assigned.add(col);
          break;
        }
      }
    }
    // Bonus: more assigned columns = more likely a header row
    score += assigned.size;
    if (score > bestScore) {
      bestScore = score;
      bestIdx = i;
    }
  }

  // If no header-like row found, return -1 to signal headerless input
  return bestIdx;
}

/**
 * Detect columns from a header row using alias matching.
 * Each column index can only be assigned to one field.
 */
function detectColumnsFromHeader(headerRow: string[]): ColumnMap {
  const colMap: ColumnMap = {};
  const assigned = new Set<number>();

  // First pass: exact alias matches
  for (let col = 0; col < headerRow.length; col++) {
    const headerNorm = normalizeHeader(headerRow[col] || "");
    if (headerNorm.length < 2) continue;

    for (const fieldKey of Object.keys(HEADER_ALIASES)) {
      if (assigned.has(col)) break;
      if (headerMatchesAlias(headerNorm, fieldKey)) {
        (colMap as Record<string, number>)[fieldKey] = col;
        assigned.add(col);
        break;
      }
    }
  }

  // Second pass: if no date column found, look for date-like headers
  if (colMap.transactionDate === undefined) {
    for (let col = 0; col < headerRow.length; col++) {
      if (assigned.has(col)) continue;
      const headerNorm = normalizeHeader(headerRow[col] || "");
      if (/date/.test(headerNorm) && !DENYLIST_DATE_PATTERNS.some(p => p.test(headerNorm))) {
        if (colMap.transactionDate === undefined) {
          colMap.transactionDate = col;
        } else if (colMap.postDate === undefined) {
          colMap.postDate = col;
        }
        assigned.add(col);
      }
    }
  }

  // Third pass: if still no postDate but we have transactionDate, use the
  // same column (some CSVs only have one date column)
  if (colMap.transactionDate !== undefined && colMap.postDate === undefined) {
    colMap.postDate = colMap.transactionDate;
  }

  return colMap;
}

/**
 * Heuristic fallback: infer columns from data content when headers don't match.
 * Score each column by (a) fraction of parseable dates → date candidates,
 * (b) fraction of parseable amounts → amount, (c) mean text length → description.
 */
function inferColumnsFromData(rows: string[][], startIndex: number): ColumnMap {
  const colMap: ColumnMap = {};
  const assigned = new Set<number>();
  const maxCol = Math.max(...rows.map(r => r.length));

  // Score each column for each characteristic
  const dateScores: number[] = [];
  const amountScores: number[] = [];
  const textScores: number[] = [];

  for (let col = 0; col < maxCol; col++) {
    let dateCount = 0;
    let amountCount = 0;
    let textTotal = 0;
    let nonEmpty = 0;

    for (let row = startIndex; row < rows.length; row++) {
      const val = rows[row][col];
      if (!val || !val.trim()) continue;
      nonEmpty++;

      if (parseDateCell(val.trim()) !== null) dateCount++;
      const amt = parseAmountCell(val.trim());
      if (amt !== null) amountCount++;
      textTotal += val.trim().length;
    }

    dateScores[col] = nonEmpty > 0 ? dateCount / nonEmpty : 0;
    amountScores[col] = nonEmpty > 0 ? amountCount / nonEmpty : 0;
    textScores[col] = nonEmpty > 0 ? textTotal / nonEmpty : 0;
  }

  // Assign date columns (highest date scores, at least 0.5 threshold)
  const dateCols = [...dateScores.entries()]
    .filter(([_, score]) => score >= 0.5)
    .sort((a, b) => b[1] - a[1]);

  if (dateCols.length >= 1) {
    colMap.transactionDate = dateCols[0][0];
    assigned.add(dateCols[0][0]);
  }
  if (dateCols.length >= 2) {
    colMap.postDate = dateCols[1][0];
    assigned.add(dateCols[1][0]);
  }

  // Assign amount column (highest amount score among unassigned)
  const amountCols = [...amountScores.entries()]
    .filter(([col, score]) => !assigned.has(col) && score >= 0.5)
    .sort((a, b) => b[1] - a[1]);

  if (amountCols.length >= 1) {
    colMap.amount = amountCols[0][0];
    assigned.add(amountCols[0][0]);
  }

  // Assign description column (highest text score among unassigned, must have text)
  const textCols = [...textScores.entries()]
    .filter(([col, score]) => !assigned.has(col) && score >= 3)
    .sort((a, b) => b[1] - a[1]);

  if (textCols.length >= 1) {
    colMap.description = textCols[0][0];
    assigned.add(textCols[0][0]);
  }

  return colMap;
}

/* -------------------------------------------------------------------------- */
/* Value parsing                                                               */
/* -------------------------------------------------------------------------- */

/**
 * Parse an amount cell, extracting the signed numeric value.
 * Handles currency symbols, parentheses (accounting negative),
 * CR/DR markers, and various thousand/decimal separators.
 *
 * Returns the raw signed numeric value. Sign detection (which sign
 * represents a charge) is handled separately by `detectChargeSign`.
 */
function parseAmountCell(raw: string): number | null {
   if (!raw) return null;
   let str = raw.trim();
   if (!str) return null;

   let isNegative = false;

   // Handle parentheses (accounting convention: negative)
   if (str.startsWith("(") && str.endsWith(")")) {
     isNegative = true;
     str = str.slice(1, -1).trim();
   }

   // Handle explicit minus sign
   if (str.startsWith("-") || str.startsWith("−")) {
     isNegative = true;
     str = str.replace(/^[-−]+/, "").trim();
   }
   // Handle explicit plus sign
   if (str.startsWith("+")) {
     str = str.slice(1).trim();
   }

  // Remove currency symbols and 3-letter currency codes
  str = str.replace(/[$€£¥₩₹]/g, "");
  str = str.replace(/\b(USD|EUR|GBP|JPY|CAD|AUD|INR|CNY|MXN)\b/gi, "");

  // Handle European vs US decimal/thousand separators
  const hasComma = str.includes(",");
  const hasDot = str.includes(".");

  if (hasComma && !hasDot) {
    // Only commas present — could be decimal (European) or thousand separator
    // If the part after the last comma is 1-2 digits, treat comma as decimal separator
    const lastCommaPart = str.split(",").pop() || "";
    if (lastCommaPart.length === 1 || lastCommaPart.length === 2) {
      // Last comma is the decimal separator
      const parts = str.split(",");
      const decimal = parts.pop();
      str = parts.join("") + "." + decimal;
    } else {
      // Multiple digits after comma → thousand separator, just remove
      str = str.replace(/,/g, "");
    }
  } else if (hasComma && hasDot) {
    // Both present: determine which is the separator
    // European: "1.234,56" (dot = thousands, comma = decimal)
    // US: "1,234.56" (comma = thousands, dot = decimal)
    const lastCommaPart = str.split(",").pop() || "";
    const lastDotPart = str.split(".").pop() || "";
    // If comma-part is 1-2 digits and dot-part is 3 digits, it's European
    if ((lastCommaPart.length === 1 || lastCommaPart.length === 2) && lastDotPart.length === 3) {
      str = str.replace(/\./g, "").replace(",", ".");
    } else {
      // US format: remove commas
      str = str.replace(/,/g, "");
    }
  } else {
    // No commas or only dots — just remove any remaining commas
    str = str.replace(/,/g, "");
  }

  const value = parseFloat(str);
  if (isNaN(value) || !isFinite(value)) return null;

   return isNegative ? -value : value;
 }

/**
 * Parse a date cell into ISO YYYY-MM-DD format.
 * Handles many common formats. Returns null if the string is not a valid date.
 */
function parseDateCell(raw: string): string | null {
  if (!raw || !raw.trim()) return null;
  const str = raw.trim();

  // ISO format: YYYY-MM-DD or YYYY/MM/DD
  let m = /^(\d{4})[-/](\d{1,2})[-/](\d{1,2})/.exec(str);
  if (m) {
    const y = m[1];
    const mo = m[2].padStart(2, "0");
    const d = m[3].padStart(2, "0");
    return `${y}-${mo}-${d}`;
  }

  // MM/DD/YYYY or DD/MM/YYYY (handles both / and - separators)
  m = /^(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})$/.exec(str);
  if (m) {
    const p1 = parseInt(m[1]);
    const p2 = parseInt(m[2]);
    if (p1 > 12 && p2 <= 12) {
      // DD/MM/YYYY — first part is day
      return parseMonthDayYear(m[2], m[1], m[3]);
    }
    if (p1 <= 12 && p2 > 12) {
      // MM/DD/YYYY — first part is month
      return parseMonthDayYear(m[1], m[2], m[3]);
    }
    if (p1 > 12 && p2 > 12) {
      // Neither fits → can't parse
      return null;
    }
    // Ambiguous (both <= 12) — default to US format (MM/DD/YYYY)
    return parseMonthDayYear(m[1], m[2], m[3]);
  }

  // Text month formats: "5 Jan 2026", "05-Jan-2026", "Jan 5, 2026"
  m = /^(\d{1,2})[-\s]([A-Za-z]{3,9})[-\s](\d{4})$/.exec(str);
  if (m) {
    const day = m[1].padStart(2, "0");
    const month = monthNameToNumber(m[2]);
    if (month) return `${m[3]}-${month}-${day}`;
  }

  m = /^([A-Za-z]{3,9})[-\s](\d{1,2}),?\s+(\d{4})$/.exec(str);
  if (m) {
    const month = monthNameToNumber(m[1]);
    if (month) return `${m[3]}-${month}-${m[2].padStart(2, "0")}`;
  }

  return null;
}

function parseMonthDayYear(month: string, day: string, year: string): string | null {
  const mo = parseInt(month);
  const d = parseInt(day);
  const y = parseInt(year);
  if (isNaN(mo) || isNaN(d) || isNaN(y)) return null;
  if (mo < 1 || mo > 12) return null;
  if (d < 1 || d > 31) return null;
  return `${y}-${mo.toString().padStart(2, "0")}-${d.toString().padStart(2, "0")}`;
}

const MONTH_NAMES: Record<string, string> = {
  jan: "01", feb: "02", mar: "03", apr: "04", mai: "05", may: "05",
  jun: "06", jul: "07", aug: "08", sep: "09", sept: "09", oct: "10",
  nov: "11", dec: "12",
};

function monthNameToNumber(name: string): string | null {
  const normalized = name.toLowerCase().replace(/[^a-z]/g, "");
  const result = MONTH_NAMES[normalized];
  return result ?? null;
}

/** Resolve currency: per-row column → optional options param → "USD" */
function resolveCurrency(rowCurrency: string | undefined, optionsCurrency?: string): string {
  const candidates = [rowCurrency, optionsCurrency, "USD"];
  for (const c of candidates) {
    if (c && c.trim()) {
      const upper = c.trim().toUpperCase().replace(/[^A-Z]/g, "");
      if (/^[A-Z]{3}$/.test(upper)) return upper;
    }
  }
  return "USD";
}

/**
 * Determine which sign in the raw CSV represents a charge (purchase).
 * Uses the Type column when available, falls back to majority distribution.
 */
function detectChargeSign(
  entries: { raw: number; type: string; description: string }[],
): { chargeSign: "positive" | "negative"; signFlipped: boolean } {
  const chargeTypes = new Set(["sale", "purchase", "debit", "charge", "pos", "point of sale"]);
  const paymentTypes = new Set(["payment", "credit", "return", "refund", "deposit", "transfer", "adjustment"]);

  let chargePositive = 0;
  let chargeNegative = 0;
  let paymentPositive = 0;
  let paymentNegative = 0;
  let totalPositive = 0;
  let totalNegative = 0;
  let total = 0;

  for (const entry of entries) {
    const raw = entry.raw;
    const type = entry.type.toLowerCase().trim();
    if (raw === 0) continue;

    const isChargeType = chargeTypes.has(type);
    const isPaymentType = paymentTypes.has(type);

    if (raw > 0) {
      totalPositive++;
      if (isChargeType) chargePositive++;
      if (isPaymentType) paymentPositive++;
    } else {
      totalNegative++;
      if (isChargeType) chargeNegative++;
      if (isPaymentType) paymentNegative++;
    }
    total++;
  }

  // Priority 1: If we have type-tagged charge/payment rows, use their signs
  if (chargePositive > 0 || chargeNegative > 0) {
    const chargePositiveCount = chargePositive;
    const chargeNegativeCount = chargeNegative;
    // If charges are predominantly negative, we need to flip
    if (chargeNegativeCount > chargePositiveCount) {
      return { chargeSign: "negative", signFlipped: true };
    }
    return { chargeSign: "positive", signFlipped: false };
  }

  if (paymentPositive > 0 || paymentNegative > 0) {
    // If payments are predominantly positive, charges are negative (need flip)
    // If payments are predominantly negative, charges are already positive
    if (paymentPositive > paymentNegative) {
      return { chargeSign: "negative", signFlipped: true };
    }
    return { chargeSign: "positive", signFlipped: false };
  }

  // Priority 2: No type column or unrecognized types — use majority distribution
  // If most amounts are negative, charges are likely negative (need flip)
  if (totalNegative > totalPositive && total > 0) {
    return { chargeSign: "negative", signFlipped: true };
  }

  // Default: assume charges are positive (no flip needed)
  return { chargeSign: "positive", signFlipped: false };
}

/* -------------------------------------------------------------------------- */
/* Last-4 extraction                                                           */
/* -------------------------------------------------------------------------- */

/**
 * Extract the last 4 digits of a card number from a description string.
 * Handles multiple formats: *1234, ending in 1234, ending with XXXX-XXXX-XXXX-1234, etc.
 */
function extractLast4(description: string): string | undefined {
  if (!description) return undefined;

  // Pattern: *1234, * 1234, ••••1234, etc. (Chase format)
  let m = /(?:\*+|●+|x+x+|\.{3,})\s*(\d{4})\b/.exec(description);
  if (m) return m[1];

  // Pattern: "ending in 1234" or "ending 1234"
  m = /\bending\s+(?:in\s+)?(\d{4})\b/i.exec(description);
  if (m) return m[1];

  // Pattern: "1234" right before end of string, preceded by non-digit
  m = /\s(\d{4})\s*$/.exec(description);
  if (m) return m[1];

  // Pattern: XXXX-XXXX-XXXX-1234 or XXXX XXXX XXXX 1234
  m = /(?:x+[- ]?){3}(\d{4})\b/i.exec(description);
  if (m) return m[1];

  // Pattern: last 4 digits of a longer digit sequence (e.g., "1234567890121234")
  m = /\d{8,16}(\d{4})\b/.exec(description);
  if (m) return m[1];

  return undefined;
}

/* -------------------------------------------------------------------------- */
/* Category mapping                                                            */
/* -------------------------------------------------------------------------- */

/**
 * Normalize a category string from any bank CSV to a Plaid personal_finance_category primary.
 * Falls back to the raw trimmed category if no match is found.
 *
 * Plaid-defined primary category values. The old `mapChaseCategory` is kept
 * as an alias for backward compatibility.
 */
export function normalizeCategory(cat: string): string {
  if (!cat || !cat.trim()) return "";
  const normalized = cat.toLowerCase().trim();

  // Order matters: check more specific patterns first
  if (/food|restaurant|dining|coffee|cafe|grocer|supermarket|alcohol|bar/.test(normalized)) {
    return "FOOD_AND_DRINK";
  }
  if (/travel|airline|hotel|lodging|flight|cruise|car.?rental/.test(normalized)) {
    return "TRAVEL";
  }
  if (/gas|fuel|petrol|transit|parking|uber|lyft|transport|commute/.test(normalized)) {
    return "TRANSPORTATION";
  }
  if (/shop|merchandise|retail|electronics|clothing|apparel|book|amazon|store/.test(normalized)) {
    return "GENERAL_MERCHANDISE";
  }
  if (/home|improvement|hardware|garden|furniture|appliance/.test(normalized)) {
    return "HOME_IMPROVEMENT";
  }
  if (/entertain|movie|music|game|streaming|recreation|subscription/.test(normalized)) {
    return "ENTERTAINMENT";
  }
  if (/health|medical|pharmacy|drug|dental|vision|doctor|hospital/.test(normalized)) {
    return "MEDICAL";
  }
  if (/personal|care|salon|spa|barber|beauty|grooming/.test(normalized)) {
    return "PERSONAL_CARE";
  }
  if (/utilit|bill|phone|internet|insurance|rent|mortgage|tax/.test(normalized)) {
    return "RENT_AND_UTILITIES";
  }
  if (/income|salary|payroll|deposit|wage/.test(normalized)) {
    return "INCOME";
  }
  if (/loan|payment|autopay|finance/.test(normalized)) {
    return "LOAN_PAYMENTS";
  }
  if (/fee|interest|charge|late|overlimit/.test(normalized)) {
    return "BANK_FEES";
  }
  if (/transfer|atm|withdrawal|deposit/.test(normalized)) {
    return "TRANSFER";
  }

  // Unknown category — return the raw value for the user to see
  return cat.trim();
}

/** Alias for backward compatibility. */
export const mapChaseCategory = normalizeCategory;

/* -------------------------------------------------------------------------- */
/* Type normalization                                                          */
/* -------------------------------------------------------------------------- */

/**
 * Normalize a transaction type to one of: purchase, payment, return, adjustment,
 * transfer, or "purchase" as the default.
 *
 * The optional `amount` parameter enables sign-based fallback classification
 * when the type column is missing or unrecognizable: positive amounts are
 * treated as purchases, negative as payments.
 */
export function normalizeType(type: string, amount?: number): string {
  const t = (type || "").toLowerCase().trim();

  if (t === "return" || t === "refund") return "return";
  if (t === "payment" || t === "credit") return "payment";
  if (t === "adjustment") return "adjustment";
  if (t === "transfer") return "transfer";
  if (t === "sale" || t === "purchase" || t === "debit" || t === "charge" || t === "pos") {
    return "purchase";
  }

  // Fallback: classify by amount sign if type is unrecognized
  if (amount !== undefined && !isNaN(amount)) {
    return amount > 0 ? "purchase" : "payment";
  }

  return "purchase";
}

/* -------------------------------------------------------------------------- */
/* Date normalization (kept for backward compat — used by csvTransactionId)   */
/* -------------------------------------------------------------------------- */

export function normalizeDate(dateStr: string): string {
  if (!dateStr) return "";
  // Delegate to the more robust parser, falling back to the original
  // behavior for formats it doesn't handle
  const parsed = parseDateCell(dateStr);
  if (parsed) return parsed;

  // Fallback: original logic for edge cases
  const parts = dateStr.split(/[-\/]/);
  if (parts.length !== 3) return dateStr;
  if (parts[0].length === 4) {
    return `${parts[0]}-${parts[1].padStart(2, '0')}-${parts[2].padStart(2, '0')}`;
  }
  return `${parts[2]}-${parts[0].padStart(2, '0')}-${parts[1].padStart(2, '0')}`;
}

/* -------------------------------------------------------------------------- */
/* Sequence matcher (local copy — used for duplicate detection)                */
/* -------------------------------------------------------------------------- */

function sequenceMatcherRatio(a: string, b: string): number {
  if (!a && !b) return 1;
  if (!a || !b) return 0;
  const total = a.length + b.length;
  let matches = 0;

  function findMatches(a1: number, a2: number, b1: number, b2: number): void {
    const [i, j, k] = findLongestMatch(a, b, a1, a2, b1, b2);
    if (k > 0) {
      matches += k;
      if (i > a1 && j > b1) findMatches(a1, i, b1, j);
      if (i + k < a2 && j + k < b2) findMatches(i + k, a2, j + k, b2);
    }
  }

  findMatches(0, a.length, 0, b.length);
  return (2 * matches) / total;
}

function findLongestMatch(
  a: string, b: string,
  aStart: number, aEnd: number,
  bStart: number, bEnd: number,
): [number, number, number] {
  let bestI = aStart;
  let bestJ = bStart;
  let bestSize = 0;

  const b2j = new Map<string, number[]>();
  for (let j = bStart; j < bEnd; j++) {
    const ch = b[j]!;
    if (!b2j.has(ch)) b2j.set(ch, []);
    b2j.get(ch)!.push(j);
  }

  let j2Len = new Map<number, number>();
  for (let i = aStart; i < aEnd; i++) {
    const ch = a[i]!;
    const indices = b2j.get(ch);
    if (!indices) {
      j2Len.clear();
      continue;
    }
    const newJ2Len = new Map<number, number>();
    for (const j of indices) {
      if (j < bStart) continue;
      if (j >= bEnd) break;
      const k = (j2Len.get(j - 1) || 0) + 1;
      newJ2Len.set(j, k);
      if (k > bestSize) {
        bestI = i - k + 1;
        bestJ = j - k + 1;
        bestSize = k;
      }
    }
    j2Len = newJ2Len;
  }

  return [bestI, bestJ, bestSize];
}

/* -------------------------------------------------------------------------- */
/* Transaction ID generation                                                   */
/* -------------------------------------------------------------------------- */

/**
 * Generate a deterministic transaction_id for a CSV-imported row.
 *
 * The amount in the key uses Math.abs to be sign-agnostic, so the same
 * transaction gets the same ID regardless of which sign convention the
 * source bank uses.
 */
export async function csvTransactionId(accountId: string, row: CsvRow): Promise<string> {
  const key = [
    accountId,
    normalizeDate(row.postDate),
    normalizeDate(row.transactionDate),
    Math.round(Math.abs(row.amount) * 100), // absolute cents — sign-agnostic
    normalizeMerchant(row.description),
    normalizeType(row.type),
  ].join("|");

  const hashBuffer = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(key));
  const hashHex = Array.from(new Uint8Array(hashBuffer)).map((b) => b.toString(16).padStart(2, "0")).join("");
  return `csv_${hashHex.slice(0, 32)}`;
}

/**
 * Generate a legacy-style transaction_id that matches the IDs produced by
 * the pre-refactor parser (which used the SIGNED raw amount in the hash key).
 *
 * For Chase files where charges were negative in the raw CSV, the old code
 * produced IDs with negative cents (e.g., -9108). This function reproduces
 * that key by negating the normalized amount (which is positive for charges),
 * yielding the same signed-cents value the old parser used.
 *
 * Used in `confirmCsvImport` to detect duplicates against previously imported
 * rows, ensuring idempotent re-imports across the refactor boundary.
 */
export async function legacyCsvTransactionId(accountId: string, row: CsvRow): Promise<string> {
  const key = [
    accountId,
    normalizeDate(row.postDate),
    normalizeDate(row.transactionDate),
    Math.round(-row.amount * 100), // negated to match old signed convention
    normalizeMerchant(row.description),
    normalizeType(row.type),
  ].join("|");

  const hashBuffer = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(key));
  const hashHex = Array.from(new Uint8Array(hashBuffer)).map((b) => b.toString(16).padStart(2, "0")).join("");
  return `csv_${hashHex.slice(0, 32)}`;
}

/* -------------------------------------------------------------------------- */
/* Main parser entry point                                                     */
/* -------------------------------------------------------------------------- */

const NON_TRANSACTION_MARKERS = /^(total|balance|subtotal|statement|subtotal\s*\(|closing\s*balance)/i;

/**
 * Parse CSV transaction text into structured rows, auto-detecting columns,
 * date formats, currency, and amount sign convention.
 *
 * The resulting `CsvRow.amount` is normalized to Plaid convention:
 * **positive** for charges/purchases, **negative** for payments/credits.
 *
 * `parseChaseCsv` is kept as an alias for backward compatibility.
 */
export function parseCsvTransactions(
  text: string,
  options?: { currency?: string },
): ParsedCsv {
  const delimiter = sniffDelimiter(text);
  const rows = parseCsv(text, delimiter);
  if (rows.length < 2) throw new Error("CSV appears empty");

  const headerRowIndex = findHeaderRow(rows);
  const hasHeader = headerRowIndex >= 0;
  const headerRow = hasHeader ? rows[headerRowIndex] : [];

  let colMap: ColumnMap = {};
  if (hasHeader) {
    colMap = detectColumnsFromHeader(headerRow);
  }

  // Fallback to data-driven column inference if header matching found nothing
  if (!colMap.description && !colMap.amount && !colMap.debit && !colMap.credit) {
    const dataStart = hasHeader ? headerRowIndex + 1 : 0;
    const inferred = inferColumnsFromData(rows, dataStart);
    if (inferred.description && (inferred.amount || inferred.debit || inferred.credit)) {
      colMap = inferred;
    }
  }

  if (!colMap.description) {
    const foundHeaders = hasHeader ? headerRow.join(", ") : "(no header row detected; columns inferred from data)";
    throw new Error(
      `Could not detect CSV columns. Headers found: ${foundHeaders}. ` +
      `Please ensure the CSV has recognizable headers (e.g., Date, Description, Amount).`,
    );
  }

  if (colMap.amount === undefined && colMap.debit === undefined && colMap.credit === undefined) {
    throw new Error("Could not detect an Amount, Debit, or Credit column in the CSV.");
  }

  const parsedRows: CsvRow[] = [];
  const signEntries: { raw: number; type: string; description: string }[] = [];
  const hasDebitCreditColumns = colMap.debit !== undefined && colMap.credit !== undefined;

  const dataStartRow = hasHeader ? headerRowIndex + 1 : 0;
  for (let r = dataStartRow; r < rows.length; r++) {
    const cols = rows[r];
    if (cols.length === 0) continue;
    // Skip completely empty rows
    if (cols.every(c => !c || c.trim() === "")) continue;

    const get = (idx: number | undefined) =>
      idx !== undefined ? (cols[idx]?.trim() ?? "") : "";

    const description = get(colMap.description);

    // Skip total/balance/summary rows
    if (description && NON_TRANSACTION_MARKERS.test(description)) continue;
    // Skip rows with empty descriptions (often page breaks or spacers)
    if (!description || description.toLowerCase().trim() === "") {
      continue;
    }

    const typeRaw = get(colMap.type);
    const type = normalizeType(typeRaw);

    // Skip balance/summary rows
    if (["balance", "summary"].includes(type)) continue;

    let rawAmount: number | null;

    if (hasDebitCreditColumns) {
      // Debit/Credit split columns: debit = charge (positive), credit = payment (negative)
      const debitRaw = get(colMap.debit);
      const creditRaw = get(colMap.credit);
      const debitAmount = parseAmountCell(debitRaw);
      const creditAmount = parseAmountCell(creditRaw);

      if (debitAmount !== null && debitAmount > 0) {
        rawAmount = Math.abs(debitAmount); // charge → positive
      } else if (creditAmount !== null && creditAmount > 0) {
        rawAmount = -Math.abs(creditAmount); // payment → negative
      } else {
        continue; // No amount in either column, skip
      }
    } else {
      rawAmount = parseAmountCell(get(colMap.amount));
    }

    if (rawAmount === null || rawAmount === 0) continue;

    const row: CsvRow = {
       transactionDate: get(colMap.transactionDate) || "",
       postDate: get(colMap.postDate) || "",
       description,
       category: normalizeCategory(get(colMap.category)),
       type: typeRaw,
       amount: rawAmount,
       currency: resolveCurrency(get(colMap.currency), options?.currency),
       memo: get(colMap.memo),
     };

    parsedRows.push(row);
    signEntries.push({ raw: rawAmount, type: typeRaw, description: row.description });
  }

  if (parsedRows.length === 0) {
    throw new Error("No transaction rows found in the CSV. Please check the format and column headers.");
  }

  // Detect and apply sign convention (only for single-amount-column files)
  // For Debit/Credit split files, per-row signs are already correct.
  let chargeSign: "positive" | "negative" = "positive";
  let signFlipped = false;

  if (!hasDebitCreditColumns) {
    const { chargeSign: detected, signFlipped: flipped } = detectChargeSign(signEntries);
    chargeSign = detected;
    signFlipped = flipped;

    if (flipped) {
      for (const row of parsedRows) {
        row.amount = -row.amount;
      }
    }
  }

  // Extract card last-4 from descriptions (use most common if appears 2+ times)
  let detectedCardLast4: string | undefined;
  const last4Counts = new Map<string, number>();
  for (const row of parsedRows) {
    const last4 = extractLast4(row.description);
    if (last4) {
      last4Counts.set(last4, (last4Counts.get(last4) ?? 0) + 1);
    }
  }
  for (const [last4, count] of last4Counts) {
    if (count >= 2) {
      if (!detectedCardLast4 || count > (last4Counts.get(detectedCardLast4) ?? 0)) {
        detectedCardLast4 = last4;
      }
    }
  }

  // Determine detected currency (the non-USD one if present, or the options currency)
  let detectedCurrency: string | undefined;
  for (const row of parsedRows) {
    if (row.currency !== "USD") {
      detectedCurrency = row.currency;
      break;
    }
  }
  if (!detectedCurrency && options?.currency) {
    detectedCurrency = options.currency;
  }

  return {
    rows: parsedRows,
    detectedCardName: undefined,
    detectedCardLast4,
    detectedCurrency,
    chargeSign,
    signFlipped,
    detectedColumns: colMap,
  };
}

/* -------------------------------------------------------------------------- */
/* Existing transaction fetching & duplicate matching                          */
/* -------------------------------------------------------------------------- */

const PAGE_SIZE = 500;
const DATE_TOLERANCE_DAYS = 1;

interface ExistingTxn {
  transaction_id: string;
  account_id: string;
  amount: number;
  date: string;
  authorized_date: string | null;
  merchant_name: string | null;
  name: string | null;
  original_description: string | null;
  is_removed: boolean | null;
}

async function fetchExistingTransactions(userId: string, accountId: string): Promise<ExistingTxn[]> {
  const all: ExistingTxn[] = [];
  for (let from = 0; from < 50_000; from += PAGE_SIZE) {
    const { data, error } = await supabase
      .from("plaid_transactions")
      .select("transaction_id, account_id, amount, date, authorized_date, merchant_name, name, original_description, is_removed")
      .eq("account_id", accountId)
      .eq("user_id", userId)
      .order("transaction_id", { ascending: true })
      .range(from, from + PAGE_SIZE - 1);
    if (error) throw new Error(`Failed to load existing transactions: ${error.message}`);
    all.push(...(data ?? []));
    if (!data || data.length < PAGE_SIZE) break;
  }
  return all;
}

interface DateCandidate {
  csvDate: string;
  dateType: 'posted' | 'authorized';
}

function findBestMatchForDateAmount(
  existingTxns: ExistingTxn[],
  targetMerchant: string,
  targetAmountCents: number,
  candidates: DateCandidate[],
  matchedTxIds: Set<string>,
): { match: ExistingTxn; matchScore: number; dateDistance: number; csvDate: string; dbDate: string } | null {
  let bestMatch: ExistingTxn | null = null;
  let bestScore = 0;
  let bestDateDist = 0;
  let bestCsvDate = "";
  let bestDbDate = "";

  for (const tx of existingTxns) {
    // Skip already matched transactions
    if (matchedTxIds.has(tx.transaction_id)) continue;

    for (const cand of candidates) {
      const txDate = cand.dateType === 'posted' ? tx.date : tx.authorized_date;
      if (!txDate) continue;

      // Allow date tolerance for matching
      const dateDist = dateDistanceDays(txDate, cand.csvDate);
      if (dateDist === null || dateDist > DATE_TOLERANCE_DAYS) continue;

      const txAmountCents = Math.round(Math.abs(Number(tx.amount)) * 100);
      if (txAmountCents !== targetAmountCents) continue;

      const txMerchant = normalizeMerchant(tx.merchant_name || tx.name || "");
      if (!txMerchant || !targetMerchant) continue;

      const score = sequenceMatcherRatio(targetMerchant, txMerchant);
      // Higher threshold for closer dates; require >=0.6 minimum
      const minScore = dateDist === 0 ? 0.6 : 0.7;
      if (score > bestScore && score >= minScore) {
        bestScore = score;
        bestDateDist = dateDist;
        bestMatch = tx;
        bestCsvDate = cand.csvDate;
        bestDbDate = txDate;
      }
    }
  }

  if (bestMatch) {
    return { match: bestMatch, matchScore: bestScore, dateDistance: bestDateDist, csvDate: bestCsvDate, dbDate: bestDbDate };
  }
  return null;
}

/* -------------------------------------------------------------------------- */
/* Date utility (for duplicate matching)                                      */
/* -------------------------------------------------------------------------- */

function parseIsoDate(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(value.trim());
  return m ? Date.UTC(+m[1], +m[2] - 1, +m[3]) : null;
}

function dateDistanceDays(a: unknown, b: unknown): number | null {
  if (typeof a !== "string" || typeof b !== "string") return null;
  const da = parseIsoDate(a), db = parseIsoDate(b);
  if (da === null || db === null) return null;
  return Math.abs((da - db) / 86_400_000);
}

/* -------------------------------------------------------------------------- */
/* Preview & Confirm                                                          */
/* -------------------------------------------------------------------------- */

/**
 * Generate a preview of a CSV import, showing which rows are new, duplicate,
 * or errored. Uses the universal parser.
 *
 * `options.currency` allows the caller (API route) to specify a default
 * currency if the CSV doesn't contain a currency column.
 */
export async function generateCsvPreview(
  userId: string,
  accountId: string,
  csvText: string,
  options?: { currency?: string },
): Promise<CsvPreviewResult> {
  const parsed = parseCsvTransactions(csvText, options);

  const { data: account, error: accountError } = await supabase
    .from("plaid_credit_accounts")
    .select("account_id, mask, name, official_name, institution_name")
    .eq("account_id", accountId)
    .eq("user_id", userId)
    .single();

  if (accountError || !account) {
    throw new Error("Account not found or access denied");
  }

  let accountValidation: CsvPreviewResult["accountValidation"] = { matched: true };
  if (parsed.detectedCardLast4 && account.mask) {
    const csvLast4 = parsed.detectedCardLast4;
    const plaidLast4 = account.mask.slice(-4);
    if (csvLast4 !== plaidLast4) {
      accountValidation = {
        matched: false,
        warning: `CSV appears to be for card ending in ${csvLast4}, but selected account ends in ${plaidLast4}`,
      };
    }
  }

  const existingTxns = await fetchExistingTransactions(userId, accountId);

  console.log(`[CSV Import] Found ${existingTxns.length} existing Plaid transactions for account ${accountId}`);

  // Track matched DB transaction IDs to prevent multiple CSV rows matching same DB txn
  const matchedTxIds = new Set<string>();

  const preview: PreviewRow[] = [];
  for (const row of parsed.rows) {
    const amountCents = Math.round(Math.abs(row.amount) * 100);
    const normMerchant = normalizeMerchant(row.description);

    // Try all date combinations: CSV postDate/transDate vs DB date/authorized_date
    const allCandidates: DateCandidate[] = [];
    const normPostDate = normalizeDate(row.postDate);
    const normTransDate = normalizeDate(row.transactionDate);

    if (normPostDate) {
      allCandidates.push({ csvDate: normPostDate, dateType: 'posted' });
      allCandidates.push({ csvDate: normPostDate, dateType: 'authorized' });
    }
    if (normTransDate) {
      allCandidates.push({ csvDate: normTransDate, dateType: 'posted' });
      allCandidates.push({ csvDate: normTransDate, dateType: 'authorized' });
    }

    // Validate dates — use parseDateCell for robust validation
    const postDateValid = row.postDate ? parseDateCell(row.postDate) !== null : false;
    const transDateValid = row.transactionDate ? parseDateCell(row.transactionDate) !== null : false;

    if (!postDateValid && !transDateValid) {
      preview.push({
        row,
        status: "error",
        error: "Row has unparseable dates",
      });
      continue;
    }

    const match = findBestMatchForDateAmount(existingTxns, normMerchant, amountCents, allCandidates, matchedTxIds);

    if (match) {
      matchedTxIds.add(match.match.transaction_id as string);
      preview.push({ row, status: "duplicate", match: match.match as unknown as Record<string, unknown>, matchScore: match.matchScore });
      continue;
    }

    preview.push({ row, status: "new" });
  }

  const summary = preview.reduce(
    (acc, p) => {
      acc[p.status]++;
      return acc;
    },
    { new: 0, duplicate: 0, error: 0 },
  );

  return {
    preview,
    summary,
    accountValidation,
    detectedCurrency: parsed.detectedCurrency,
    chargeSign: parsed.chargeSign,
    signFlipped: parsed.signFlipped,
  };
}

/**
 * Build a database record from a CSV row, in the Plaid transaction shape.
 * Extracted as a pure function for testability.
 */
export function buildTransactionRecord(
  accountId: string,
  userId: string,
  row: CsvRow,
  currency: string,
): Record<string, unknown> {
  return {
    transaction_id: "",  // filled by caller via csvTransactionId
    account_id: accountId,
    amount: row.amount, // Already normalized to Plaid convention (positive=charge)
    iso_currency_code: currency,
    date: normalizeDate(row.postDate),
    authorized_date: normalizeDate(row.transactionDate) || null,
    name: row.description,
    merchant_name: row.description,
    original_description: row.description,
    personal_finance_category_primary: normalizeCategory(row.category),
    transaction_code: normalizeType(row.type, row.amount),
    transaction_type: normalizeType(row.type, row.amount),
    pending: false,
    user_id: userId,
    is_removed: false,
    source: "csv_import",
    synced_at: new Date().toISOString(),
  };
}

export async function confirmCsvImport(
  userId: string,
  accountId: string,
  rows: CsvRow[],
  filename: string,
  options?: { currency?: string },
): Promise<{ inserted: number; duplicates: number; errors: string[] }> {
  const { data: account } = await supabase
    .from("plaid_credit_accounts")
    .select("account_id, item_id, user_id")
    .eq("account_id", accountId)
    .eq("user_id", userId)
    .single();

  if (!account) throw new Error("Account not found");

  // Fetch existing transactions for duplicate checking
  const existingTxns = await fetchExistingTransactions(userId, accountId);
  const existingTxIdSet = new Set(existingTxns.map(t => t.transaction_id));

  // Track matched DB transaction IDs to prevent multiple CSV rows matching same DB txn
  const matchedTxIds = new Set<string>();

  const records: Record<string, unknown>[] = [];
  const errors: string[] = [];
  let duplicates = 0;
  const resolvedCurrency = resolveCurrency(undefined, options?.currency);

  for (const row of rows) {
    try {
      const amountCents = Math.round(Math.abs(row.amount) * 100);
      const normMerchant = normalizeMerchant(row.description);
      const allCandidates: DateCandidate[] = [];
      const normPostDate = normalizeDate(row.postDate);
      const normTransDate = normalizeDate(row.transactionDate);

      if (normPostDate) {
        allCandidates.push({ csvDate: normPostDate, dateType: 'posted' });
        allCandidates.push({ csvDate: normPostDate, dateType: 'authorized' });
      }
      if (normTransDate) {
        allCandidates.push({ csvDate: normTransDate, dateType: 'posted' });
        allCandidates.push({ csvDate: normTransDate, dateType: 'authorized' });
      }

      // Check for duplicate using date + amount + merchant matching
      const match = findBestMatchForDateAmount(existingTxns, normMerchant, amountCents, allCandidates, matchedTxIds);
      if (match) {
        matchedTxIds.add(match.match.transaction_id as string);
        duplicates++;
        continue;
      }

      // Check by deterministic ID (for previously CSV-imported transactions)
      // Use both the new ID (abs cents) and the legacy ID (signed cents) for
      // backward compatibility with rows imported before the refactor.
      const detId = await csvTransactionId(accountId, row);
      const legacyId = await legacyCsvTransactionId(accountId, row);

      if (existingTxIdSet.has(detId) || existingTxIdSet.has(legacyId)) {
        duplicates++;
        continue;
      }

      const record = buildTransactionRecord(accountId, userId, row, resolvedCurrency);
      record.transaction_id = detId;
      records.push(record);
    } catch (e) {
      errors.push(`Row ${row.description}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  if (records.length > 0) {
    // Use upsert with conflict handling to prevent duplicates from race conditions
    const { error } = await supabase
      .from("plaid_transactions")
      .upsert(records, { onConflict: "transaction_id" });
    if (error) throw new Error(`Insert failed: ${error.message}`);
  }

  await supabase.from("csv_import_history").insert({
    user_id: userId,
    account_id: accountId,
    filename,
    total_rows: rows.length,
    new_count: records.length,
    duplicate_count: duplicates,
    error_count: errors.length,
  });

  return { inserted: records.length, duplicates, errors };
}
