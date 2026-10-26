/**
 * Merchant-name normalization shared by reconciliation.
 *
 * Extracted from csv_match.ts so that the reconciliation layer
 * no longer depends on the CSV-import matcher.
 *
 * Differences from reconcile.ts's `normalizeMerchant` (which is hashed
 * into deterministic CSV IDs and must NOT change):
 *   - Strips apostrophes BEFORE punctuation collapse ("Domino's" → "dominos")
 *   - Strips processor prefixes and card last-4 artifacts
 *   - Removes store numbers (#1234)
 *
 * This produces cleaner tokens for matching without affecting legacy CSV ID generation.
 */

/**
 * Processor prefixes to strip (matches normalizeMerchant behavior).
 */
export const PROCESSOR_PREFIXES = ["sq", "dd", "tst", "pos", "paypal", "pp", "venmo"];

/**
 * Match-only merchant normalizer.
 */
export function normalizeMerchantForMatch(value: string | null | undefined): string {
  if (!value) return "";
  let v = String(value);

  // Unicode normalization: strip non-ASCII
  v = v.normalize("NFKD").replace(/[^\x00-\x7F]/g, "");

  // Lowercase
  v = v.toLowerCase();

  // Strip processor prefixes (e.g., "dd *", "tst*", "sq*")
  v = v.replace(new RegExp(`^(${PROCESSOR_PREFIXES.join("|")})\\s*\\*\\s*`, "i"), "");

  // Remove apostrophes and similar punctuation that splits tokens
  v = v.replace(/[''\u2019\u2018\u201A]/g, "");

  // Remove card last-4 markers (*1234, x1234, xxxx1234, etc.)
  v = v.replace(/[x*]{1,4}[\s-]?\d{4}/gi, " ");

  // Remove store numbers like #1234, # 1234
  v = v.replace(/#\s*\d+/g, " ");

  // Collapse remaining non-alphanumeric to spaces
  v = v.replace(/[^a-z0-9]+/g, " ");

  // Collapse whitespace and trim
  return v.replace(/\s+/g, " ").trim();
}
