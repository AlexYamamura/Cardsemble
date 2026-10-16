import { Decimal } from "https://esm.sh/decimal.js@10.4.3";
import { supabase } from "./supabase.ts";
import { normalizeMerchant } from "./reconcile.ts";

export interface CsvRow {
  transactionDate: string;
  postDate: string;
  description: string;
  category: string;
  type: string;
  amount: number;
  memo: string;
  currency: string;
}

export interface ParsedCsv {
  rows: CsvRow[];
  detectedCardName?: string;
  detectedCardLast4?: string;
}

export interface PreviewRow {
  row: CsvRow;
  status: "new" | "duplicate" | "error";
  match?: Record<string, unknown>;
  matchScore?: number;
  error?: string;
}

export interface CsvPreviewResult {
  preview: PreviewRow[];
  summary: { new: number; duplicate: number; error: number };
  accountValidation?: { matched: boolean; warning?: string };
}

function parseCsv(text: string): string[][] {
  const lines = text.trim().split(/\r?\n/);
  const result: string[][] = [];
  let current: string[] = [];
  let inQuotes = false;
  let cell = "";

  for (const line of lines) {
    for (let i = 0; i < line.length; i++) {
      const ch = line[i];
      if (ch === '"') {
        if (inQuotes && line[i + 1] === '"') {
          cell += '"';
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch === "," && !inQuotes) {
        current.push(cell);
        cell = "";
      } else {
        cell += ch;
      }
    }
    current.push(cell);
    result.push(current);
    current = [];
    cell = "";
    inQuotes = false;
  }
  return result;
}

export function parseChaseCsv(text: string): ParsedCsv {
  const rows = parseCsv(text);
  if (rows.length < 2) throw new Error("CSV appears empty");

  const header = rows[0].map((h) => h.trim().toLowerCase());
  const expected = [
    "transaction date",
    "post date",
    "description",
    "category",
    "type",
    "amount",
    "memo",
  ];

  const colMap: Record<string, number> = {};
  for (let i = 0; i < header.length; i++) {
    const idx = expected.indexOf(header[i]);
    if (idx >= 0) colMap[expected[idx]] = i;
  }

  for (const exp of expected) {
    if (!(exp in colMap)) throw new Error(`Missing column: ${exp}`);
  }

  let detectedCardName: string | undefined;
  let detectedCardLast4: string | undefined;

  const parsedRows: CsvRow[] = [];
  for (let r = 1; r < rows.length; r++) {
    const cols = rows[r];
    if (cols.length < header.length) continue;

    const get = (name: string) => cols[colMap[name]]?.trim() ?? "";

    const description = get("description");
    const amountStr = get("amount").replace(/[$,]/g, "");
    const amount = parseFloat(amountStr);

    if (isNaN(amount)) continue;

    const type = get("type").toLowerCase();
    if (!["sale", "payment", "credit", "return"].includes(type)) continue;

    parsedRows.push({
      transactionDate: get("transaction date"),
      postDate: get("post date"),
      description,
      category: get("category"),
      type,
      amount,
      memo: get("memo"),
      currency: "USD",
    });

    if (!detectedCardLast4 && description) {
      const last4Match = description.match(/\*(\d{4})$/);
      if (last4Match) detectedCardLast4 = last4Match[1];
    }
  }

  return { rows: parsedRows, detectedCardName, detectedCardLast4 };
}

function normalizeType(type: string): string {
  const t = type.toLowerCase();
  if (t === "sale") return "purchase";
  if (t === "payment" || t === "credit") return "payment";
  if (t === "return") return "return";
  return "purchase";
}

function normalizeDate(dateStr: string): string {
  if (!dateStr) return "";
  // Handle various date formats: MM/DD/YYYY, YYYY-MM-DD, DD/MM/YYYY
  const parts = dateStr.split(/[-\/]/);
  if (parts.length !== 3) return dateStr;
  
  // If first part is 4 digits, assume YYYY-MM-DD
  if (parts[0].length === 4) {
    return `${parts[0]}-${parts[1].padStart(2, '0')}-${parts[2].padStart(2, '0')}`;
  }
  // Otherwise assume MM/DD/YYYY
  return `${parts[2]}-${parts[0].padStart(2, '0')}-${parts[1].padStart(2, '0')}`;
}

export async function generateCsvPreview(
  userId: string,
  accountId: string,
  csvText: string,
): Promise<CsvPreviewResult> {
  const parsed = parseChaseCsv(csvText);

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

  const { data: existingTxns } = await supabase
    .from("plaid_transactions")
    .select("transaction_id, account_id, amount, date, authorized_date, merchant_name, name, original_description")
    .eq("account_id", accountId)
    .eq("user_id", userId)
    .eq("is_removed", false);

  console.log(`[CSV Import] Found ${existingTxns?.length ?? 0} existing Plaid transactions for account ${accountId}`);
  
  // Log first few existing transactions for debugging
  let count = 0;
  for (const tx of existingTxns ?? []) {
    if (count < 5) {
      console.log(`[CSV Import] Existing: ${tx.account_id}|${tx.date}|${Math.round(Math.abs(Number(tx.amount)) * 100)}|${normalizeMerchant(tx.merchant_name) || normalizeMerchant(tx.name)} | merchant: ${tx.merchant_name || tx.name} | amount: ${tx.amount} | date: ${tx.date} | auth_date: ${tx.authorized_date}`);
      count++;
    }
  }

  const preview: PreviewRow[] = [];
  for (const row of parsed.rows) {
    const plaidAmount = -row.amount;
    const amountCents = Math.round(Math.abs(plaidAmount) * 100);
    const normMerchant = normalizeMerchant(row.description);
    const normPostDate = normalizeDate(row.postDate);
    const normTransDate = normalizeDate(row.transactionDate);
    
    // Try exact match on date + amount (merchant fuzzy)
    // First try posted date
    let match = findBestMatchForDateAmount(existingTxns ?? [], normPostDate, amountCents, normMerchant, 'posted');
    let matchDateType = 'posted';
    
    // If no match, try transaction date
    if (!match && normTransDate) {
      match = findBestMatchForDateAmount(existingTxns ?? [], normTransDate, amountCents, normMerchant, 'authorized');
      matchDateType = 'authorized';
    }
    
    console.log(`[CSV Import] CSV row key (posted): ${accountId}|${normPostDate}|${amountCents}|${normMerchant} | merchant: ${row.description} | amount: ${row.amount} | postDate: ${row.postDate} -> norm: ${normPostDate}`);
    if (normTransDate) {
      console.log(`[CSV Import] CSV row key (trans):  ${accountId}|${normTransDate}|${amountCents}|${normMerchant} | transDate: ${row.transactionDate} -> norm: ${normTransDate}`);
    }

    if (match) {
      preview.push({ row, status: "duplicate", match: match.match, matchScore: match.matchScore });
      console.log(`[CSV Import] MATCH (${matchDateType} date) score=${match.matchScore} | CSV merchant: ${normMerchant} | Plaid merchant: ${normalizeMerchant((match.match.merchant_name as string) || (match.match.name as string) || "")}`);
      continue;
    }

    // No match found on either date
    preview.push({ row, status: "new" });
    console.log(`[CSV Import] NO MATCH for posted key: ${accountId}|${normPostDate}|${amountCents}|${normMerchant}${normTransDate ? ` or trans key: ${accountId}|${normTransDate}|${amountCents}|${normMerchant}` : ''}`);
  }

  const summary = preview.reduce(
    (acc, p) => {
      acc[p.status]++;
      return acc;
    },
    { new: 0, duplicate: 0, error: 0 },
  );

  return { preview, summary, accountValidation };
}

function findBestMatchForDateAmount(
  existingTxns: Record<string, unknown>[],
  targetDate: string,
  targetAmountCents: number,
  targetMerchant: string,
  dateType: 'posted' | 'authorized'
): { match: Record<string, unknown>; matchScore: number } | null {
  let bestMatch: Record<string, unknown> | null = null;
  let bestScore = 0;

  for (const tx of existingTxns) {
    const txDate = dateType === 'posted' ? (tx.date as string) : (tx.authorized_date as string);
    if (txDate !== targetDate) continue;

    const txAmountCents = Math.round(Math.abs(Number(tx.amount)) * 100);
    if (txAmountCents !== targetAmountCents) continue;

    const txMerchant = normalizeMerchant((tx.merchant_name as string) || (tx.name as string) || "");
    if (!txMerchant || !targetMerchant) continue;

    const score = sequenceMatcherRatio(targetMerchant, txMerchant);
    // Lower threshold for fuzzy matching after exact date+amount match
    if (score > bestScore && score >= 0.6) {
      bestScore = score;
      bestMatch = tx;
    }
  }

  if (bestMatch) {
    return { match: bestMatch, matchScore: bestScore };
  }
  return null;
}

export async function confirmCsvImport(
  userId: string,
  accountId: string,
  rows: CsvRow[],
  filename: string,
): Promise<{ inserted: number; errors: string[] }> {
  const { data: account } = await supabase
    .from("plaid_credit_accounts")
    .select("account_id, item_id, user_id")
    .eq("account_id", accountId)
    .eq("user_id", userId)
    .single();

  if (!account) throw new Error("Account not found");

  const records: Record<string, unknown>[] = [];
  const errors: string[] = [];

  for (const row of rows) {
    try {
      const plaidAmount = -row.amount;
      const transactionId = `csv_${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
      const normPostDate = normalizeDate(row.postDate);
      const normTransDate = normalizeDate(row.transactionDate);

      records.push({
        transaction_id: transactionId,
        account_id: accountId,
        amount: plaidAmount,
        iso_currency_code: "USD",
        date: normPostDate,
        authorized_date: normTransDate,
        name: row.description,
        merchant_name: row.description,
        original_description: row.description,
        personal_finance_category_primary: mapChaseCategory(row.category),
        transaction_code: normalizeType(row.type),
        transaction_type: normalizeType(row.type),
        pending: false,
        user_id: userId,
        is_removed: false,
        source: "csv_import",
        synced_at: new Date().toISOString(),
      });
    } catch (e) {
      errors.push(`Row ${row.description}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  if (records.length > 0) {
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
    duplicate_count: 0,
    error_count: errors.length,
  });

  return { inserted: records.length, errors };
}

function mapChaseCategory(chaseCat: string): string {
  const map: Record<string, string> = {
    "Food & Drink": "FOOD_AND_DRINK",
    "Travel": "TRAVEL",
    "Shopping": "GENERAL_MERCHANDISE",
    "Gas": "TRANSPORTATION",
    "Health & Wellness": "HEALTHCARE",
    "Entertainment": "ENTERTAINMENT",
    "Bills & Utilities": "UTILITIES",
    "Income": "INCOME",
    "Transfer": "TRANSFER",
  };
  return map[chaseCat] || "GENERAL_MERCHANDISE";
}

function sequenceMatcherRatio(a: string, b: string): number {
  if (!a && !b) return 1;
  if (!a || !b) return 0;
  const total = a.length + b.length;
  let matches = 0;

  function findMatches(a1: number, a2: number, b1: number, b2: number): void {
    let bestI = a1, bestJ = b1, bestSize = 0;
    const b2j = new Map<string, number[]>();
    for (let j = b1; j < b2; j++) {
      const ch = b[j];
      if (!b2j.has(ch)) b2j.set(ch, []);
      b2j.get(ch)!.push(j);
    }
    let j2Len = new Map<number, number>();
    for (let i = a1; i < a2; i++) {
      const ch = a[i];
      const indices = b2j.get(ch);
      if (!indices) { j2Len.clear(); continue; }
      let newJ2Len = new Map<number, number>();
      for (const j of indices) {
        if (j < b1) continue;
        if (j >= b2) break;
        const k = (j2Len.get(j - 1) || 0) + 1;
        newJ2Len.set(j, k);
        if (k > bestSize) { bestI = i - k + 1; bestJ = j - k + 1; bestSize = k; }
      }
      j2Len = newJ2Len;
    }
    if (bestSize > 0) {
      matches += bestSize;
      if (bestI > a1 && bestJ > b1) findMatches(a1, bestI, b1, bestJ);
      if (bestI + bestSize < a2 && bestJ + bestSize < b2) findMatches(bestI + bestSize, a2, bestJ + bestSize, b2);
    }
  }

  findMatches(0, a.length, 0, b.length);
  return (2 * matches) / total;
}