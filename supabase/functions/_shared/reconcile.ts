import { Decimal } from "https://esm.sh/decimal.js@10.4.3";
import { supabase } from "./supabase.ts";
import { clearDefaultPersonCache } from "./auth.ts";

async function fetchUserRows(
  table: string,
  userId: string,
  options: {
    activeOnly?: boolean;
    orderBy?: string;
  } = {},
): Promise<Record<string, unknown>[]> {
  const rows: Record<string, unknown>[] = [];
  let offset = 0;
  while (true) {
    let query = supabase
      .from(table)
      .select("*", { count: "exact" })
      .eq("user_id", userId);

    if (options.activeOnly) {
      query = query.eq("is_removed", false);
    }

    if (options.orderBy) {
      const [column, direction] = options.orderBy.split(".");
      query = query.order(column, { ascending: direction !== "desc" });
    }

    const { data, error } = await query.range(offset, offset + 499);
    if (error) throw new Error(`Could not fetch ${table}: ${error.message}`);

    if (!Array.isArray(data)) {
      throw new Error(`Could not fetch ${table}: unexpected response type ${typeof data}`);
    }
    rows.push(...data);
    if (data.length < 500) return rows;
    offset += data.length;
  }
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
    let newJ2Len = new Map<number, number>();
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

function sequenceMatcherRatio(a: string, b: string): number {
  if (a.length === 0 && b.length === 0) return 1.0;
  if (a.length === 0 || b.length === 0) return 0.0;

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

const GENERIC_CARD_NAMES = new Set([
  "credit card", "credit", "card",
  "existing linked institution", "linked institution", "unknown",
]);

export function isGenericCardName(val: string | null | undefined): boolean {
  if (!val || typeof val !== "string") return true;
  return GENERIC_CARD_NAMES.has(val.trim().toLowerCase());
}

export function creditCardDisplayName(account: Record<string, unknown>): string {
  const displayName = account.display_name;
  if (typeof displayName === "string" && displayName.trim()) {
    return displayName.trim();
  }

  const institutionName = account.institution_name;
  if (typeof institutionName === "string" && !isGenericCardName(institutionName)) {
    return institutionName.trim();
  }

  const mask = account.mask;
  if (typeof mask === "string" && mask.trim()) {
    return `Credit card ••${mask.trim()}`;
  }
  return "Credit card";
}

const PLAID_CREDIT_CARD_NAME_MAPPINGS: Record<string, string> = {
  "ultimaterewards": "Chase Freedom Unlimited",
};

export function mappedPlaidCreditCardName(officialName: string | null, name: string | null): string | null {
  for (const sourceName of [officialName, name]) {
    if (!sourceName) continue;
    const key = sourceName.toLowerCase().replace(/[^a-z0-9]/g, "");
    const mapped = PLAID_CREDIT_CARD_NAME_MAPPINGS[key];
    if (mapped) return mapped;
  }
  return null;
}

export function normalizeMerchant(value: string | null | undefined): string {
  if (!value) return "";
  let v = String(value);
  v = v.normalize("NFKD").replace(/[^\x00-\x7F]/g, "");
  v = v.toLowerCase();
  v = v.replace(/^(sq|dd|tst|pos|paypal|venmo)\s*\*?\s*/, "");
  v = v.replace(/[^a-z0-9]+/g, " ");
  return v.replace(/\s+/g, " ").trim();
}

function merchantMatchScore(event: Record<string, unknown>, transaction: Record<string, unknown>): number {
  const eventNames = new Set<string>();
  const em = normalizeMerchant(event.merchant);
  const emn = normalizeMerchant(event.merchant_name);
  if (em) eventNames.add(em);
  if (emn) eventNames.add(emn);
  if (eventNames.size === 0) return 0.0;

  const transactionFields = ["merchant_name", "name", "original_description"];
  const transactionNames = new Set<string>();
  for (const field of transactionFields) {
    const normalized = normalizeMerchant(transaction[field]);
    if (normalized) transactionNames.add(normalized);
  }
  if (transactionNames.size === 0) return 0.0;

  let best = 0.0;
  for (const eventName of eventNames) {
    for (const txName of transactionNames) {
      if (eventName === txName) return 1.0;
      if (eventName.includes(txName) || txName.includes(eventName)) {
        best = Math.max(best, 0.9);
      }
      const eventWords = new Set(eventName.split(" "));
      const txWords = new Set(txName.split(" "));
      if (eventWords.size > 0 && txWords.size > 0) {
        const intersection = new Set([...eventWords].filter((x) => txWords.has(x)));
        const union = new Set([...eventWords, ...txWords]);
        const overlap = intersection.size / union.size;
        best = Math.max(best, overlap);
        if (intersection.size === eventWords.size) {
          best = Math.max(best, 0.9);
        }
      }
      best = Math.max(best, sequenceMatcherRatio(eventName, txName));
    }
  }
  return best;
}

function parseDate(value: string | null | undefined): Date | null {
  if (!value) return null;
  try {
    return new Date(String(value).replace("Z", "+00:00"));
  } catch {
    return null;
  }
}

function eventCalendarDate(event: Record<string, unknown>): Date | null {
  return parseDate(event.occurred_at);
}

function transactionCalendarDate(transaction: Record<string, unknown>): Date | null {
  for (const field of ["datetime", "authorized_datetime", "date", "authorized_date"]) {
    const value = transaction[field];
    if (!value) continue;
    const parsed = parseDate(value);
    if (parsed) return parsed;
  }
  return null;
}

interface Candidate {
  transaction: Record<string, unknown>;
  score: number;
  merchant_similarity: number;
  date_difference_days: number | null;
  amount_difference: Decimal;
  is_tip: boolean;
  tip_percentage: number | null;
}

function reconciliationCandidates(event: Record<string, unknown>, transactions: Record<string, unknown>[]): Candidate[] {
  const eventDate = eventCalendarDate(event);
  const postedPendingIds = new Set(
    transactions
      .filter((tx) => !tx.pending && tx.pending_transaction_id)
      .map((tx) => tx.pending_transaction_id as string),
  );

  const eventCurrency = event.currency;
  const candidates: Candidate[] = [];

  for (const transaction of transactions) {
    if (
      transaction.pending &&
      postedPendingIds.has(transaction.pending_transaction_id as string)
    ) {
      continue;
    }

    const txCurrency = transaction.iso_currency_code;
    if (eventCurrency && txCurrency && String(eventCurrency).toUpperCase() !== String(txCurrency).toUpperCase()) {
      continue;
    }

    let amountDifference: Decimal;
    let isTip = false;
    let tipPercentage: number | null = null;
    try {
      const eventAmount = new Decimal(String(event.amount));
      const txAmount = new Decimal(String(transaction.amount));
      amountDifference = eventAmount.sub(txAmount).abs();

      if (txAmount.gt(eventAmount) && eventAmount.gt(0)) {
        const increase = txAmount.sub(eventAmount).div(eventAmount).mul(100);
        if (increase.gte(10) && increase.lte(25)) {
          isTip = true;
          tipPercentage = increase.toNumber();
        }
      }
    } catch {
      continue;
    }

    const merchantSimilarity = merchantMatchScore(event, transaction);
    const txDate = transactionCalendarDate(transaction);
    const dateDifference = eventDate && txDate ? Math.abs(Math.floor((eventDate.getTime() - txDate.getTime()) / (1000 * 60 * 60 * 24))) : null;

    if (dateDifference !== null && dateDifference > 3) continue;

    if (amountDifference.gt(new Decimal("0.01")) && !isTip && (merchantSimilarity < 0.60 || dateDifference === null)) {
      continue;
    }

    let score = amountDifference.lte(new Decimal("0.01")) ? 40 : isTip ? 30 : 0;
    score += merchantSimilarity >= 0.95 ? 40 : merchantSimilarity >= 0.80 ? 30 : merchantSimilarity >= 0.60 ? 20 : merchantSimilarity >= 0.40 ? 10 : 0;
    score += dateDifference === 0 ? 15 :
             dateDifference === 1 ? 10 :
             dateDifference === 2 ? 5 : 0;
    if (isTip) score += 15;

    candidates.push({
      transaction,
      score,
      merchant_similarity: merchantSimilarity,
      date_difference_days: dateDifference,
      amount_difference: amountDifference,
      is_tip: isTip,
      tip_percentage: tipPercentage,
    });
  }

  return candidates.sort((a, b) => {
    const pendingDiff = (b.transaction.pending ? 1 : 0) - (a.transaction.pending ? 1 : 0);
    if (pendingDiff !== 0) return pendingDiff;
    if (b.score !== a.score) return b.score - a.score;
    if (b.merchant_similarity !== a.merchant_similarity) {
      return b.merchant_similarity - a.merchant_similarity;
    }
    const aDateDiff = a.date_difference_days ?? 999;
    const bDateDiff = b.date_difference_days ?? 999;
    return aDateDiff - bDateDiff;
  }).slice(0, 5);
}

export async function reconcileUserCardEvents(userId: string): Promise<number> {
  const events = await fetchUserRows("card_events", userId, { orderBy: "event_id.asc" });
  const transactions = await fetchUserRows("plaid_transactions", userId, {
    activeOnly: true,
    orderBy: "transaction_id.asc",
  });

  const reconciliations: Record<string, unknown>[] = [];

  for (const event of events) {
    const candidates = reconciliationCandidates(event, transactions);
    const best = candidates.length > 0 ? candidates[0] : null;

    let status: string;
    if (!best) {
      status = "UNMATCHED";
    } else if (best.amount_difference.gt(new Decimal("0.01")) && !best.is_tip && best.amount_difference.gt(new Decimal("20"))) {
      status = "REVIEW";
    } else if (best.transaction.pending) {
      status = "PENDING";
    } else if (best.score >= 90 && best.merchant_similarity >= 0.80) {
      status = candidates.length === 1 || best.score - candidates[1].score >= 15
        ? "HIGH" : "AMBIGUOUS";
    } else if (best.score >= 70 && best.merchant_similarity >= 0.60) {
      status = candidates.length === 1 || best.score - candidates[1].score >= 20
        ? "MEDIUM" : "AMBIGUOUS";
    } else {
      status = "REVIEW";
    }

    const tx = best ? best.transaction : {};
    reconciliations.push({
      event_id: event.event_id,
      user_id: userId,
      candidate_transaction_id: tx.transaction_id ?? null,
      status,
      event_amount: event.amount,
      plaid_amount: tx.amount ?? null,
      amount_difference: best ? best.amount_difference.toFixed(2) : null,
      is_tip: best?.is_tip ?? false,
      tip_percentage: best?.tip_percentage ?? null,
      details: {
        reasons: best
          ? [
              best.amount_difference.lte(new Decimal("0.01"))
                ? "exact amount"
                : best.is_tip
                ? `possible tip: Plaid amount is ${best.tip_percentage?.toFixed(1)}% higher`
                : "Plaid posted amount differs; review required",
              `merchant similarity ${best.merchant_similarity.toFixed(3)}`,
            ]
          : ["no compatible Plaid transaction found"],
        candidate_count: candidates.length,
      },
      updated_at: new Date().toISOString(),
    });
  }

  for (let i = 0; i < reconciliations.length; i += 500) {
    const batch = reconciliations.slice(i, i + 500);
    const { error } = await supabase
      .from("card_event_reconciliations")
      .upsert(batch, { onConflict: "event_id" });
    if (error) throw new Error(`Could not save reconciliations: ${error.message}`);
  }

  return reconciliations.length;
}

export async function refreshWalletAssignments(userId: string): Promise<number> {
  const events = await fetchUserRows("card_events", userId, { orderBy: "event_id.asc" });
  const reconciliations = await fetchUserRows("card_event_reconciliations", userId, { orderBy: "event_id.asc" });
  const assignments = await fetchUserRows("transaction_assignments", userId, { orderBy: "transaction_id.asc" });

  const eventById = new Map(events.map((e) => [e.event_id as string, e]));
  const currentByTx = new Map(assignments.map((a) => [a.transaction_id as string, a]));
  const candidatesByTx = new Map<string, Array<[Record<string, unknown>, Record<string, unknown>]>>();

  for (const result of reconciliations) {
    const event = eventById.get(result.event_id as string);
    const transactionId = result.candidate_transaction_id;
    if (
      !event ||
      !event.person_id ||
      !transactionId ||
      !["HIGH", "MEDIUM"].includes(result.status as string)
    ) continue;

    const arr = candidatesByTx.get(transactionId) || [];
    arr.push([event, result]);
    candidatesByTx.set(transactionId, arr);
  }

  const updates: Record<string, unknown>[] = [];
  const ambiguousReconciliations: Record<string, unknown>[] = [];
  const desiredTransactionIds = new Set<string>();
  const now = new Date().toISOString();

  for (const [transactionId, matches] of candidatesByTx) {
    const current = currentByTx.get(transactionId);

    if (current && current.assignment_source === "manual") continue;

    if (matches.length !== 1) {
      if (current && current.assignment_source === "wallet_event") {
        await supabase
          .from("transaction_assignments")
          .delete()
          .eq("transaction_id", transactionId)
          .eq("user_id", userId);
      }
      for (const [event, reconciliation] of matches) {
        ambiguousReconciliations.push({
          ...reconciliation,
          status: "AMBIGUOUS",
          details: {
            ...(reconciliation.details as Record<string, unknown> || {}),
            assignment_issue: "Multiple Wallet events match this Plaid transaction.",
          },
          updated_at: now,
        });
      }
      continue;
    }

    const memberIds = new Set(matches.map(([e]) => e.person_id));
    if (memberIds.size !== 1) continue;

    const [event] = matches[0]!;
    desiredTransactionIds.add(transactionId);
    updates.push({
      transaction_id: transactionId,
      user_id: userId,
      person_id: event.person_id,
      assignment_source: "wallet_event",
      event_id: event.event_id,
      updated_at: now,
    });
  }

  for (const [transactionId, current] of currentByTx) {
    if (
      current.assignment_source === "wallet_event" &&
      !desiredTransactionIds.has(transactionId)
    ) {
      await supabase
        .from("transaction_assignments")
        .delete()
        .eq("transaction_id", transactionId)
        .eq("user_id", userId);
    }
  }

  if (ambiguousReconciliations.length > 0) {
    const { error } = await supabase
      .from("card_event_reconciliations")
      .upsert(ambiguousReconciliations, { onConflict: "event_id" });
    if (error) throw new Error(`Could not save ambiguous reconciliations: ${error.message}`);
  }

   // Delete existing assignments for the transactions in the batch
   const transactionIds = updates.map((u) => u.transaction_id);
   if (transactionIds.length > 0) {
     const { error: deleteError } = await supabase
       .from("transaction_assignments")
       .delete()
       .in("transaction_id", transactionIds)
       .eq("user_id", userId);
     if (deleteError) throw new Error(`Could not delete transaction assignments: ${deleteError.message}`);
   }

   // Insert wallet_event assignments with amount = null
   for (let i = 0; i < updates.length; i += 500) {
     const batch = updates.slice(i, i + 500);
     const { error } = await supabase
       .from("transaction_assignments")
       .insert(batch.map(u => ({ ...u, amount: null })))
       .error;
     if (error) throw new Error(`Could not save transaction assignments: ${error.message}`);
   }

  return updates.length;
}

function statementIssueDate(value: string | Date | null | undefined): Date | null {
  if (!value) return null;
  if (value instanceof Date) return value;
  try {
    const d = new Date(String(value));
    return isNaN(d.getTime()) ? null : d;
  } catch {
    return null;
  }
}

export async function calculateStatementSummaries(userId: string): Promise<number> {
  const primary = await import("./auth.ts").then((m) => m.ensureDefaultPerson(userId));
  const people = await fetchUserRows("household_people", userId, { orderBy: "created_at.asc,person_id.asc" });
  const accounts = await fetchUserRows("plaid_credit_accounts", userId, { orderBy: "account_id.asc" });
  const snapshots = await fetchUserRows("plaid_liability_snapshots", userId, { orderBy: "account_id.asc,statement_issue_date.asc" });
  const cycleStartOverrides = await fetchUserRows("card_cycle_start_overrides", userId, { orderBy: "account_id.asc,statement_issue_date.asc" });
  const transactions = await fetchUserRows("plaid_transactions", userId, { activeOnly: true, orderBy: "date.asc,transaction_id.asc" });
  const assignments = await fetchUserRows("transaction_assignments", userId, { orderBy: "transaction_id.asc" });
  const events = await fetchUserRows("card_events", userId, { orderBy: "occurred_at.asc,event_id.asc" });
  const reconciliations = await fetchUserRows("card_event_reconciliations", userId, { orderBy: "event_id.asc" });

  clearDefaultPersonCache(userId);

  const peopleById = new Map(people.map((p) => [p.person_id as string, p]));
  const assignmentByTx = new Map(assignments.map((a) => [a.transaction_id as string, a]));
  const eventsById = new Map(events.map((e) => [e.event_id as string, e]));
  const reconciliationByEvent = new Map(reconciliations.map((r) => [r.event_id as string, r]));

  const snapshotsByAccount = new Map<string, Record<string, unknown>[]>();
  for (const snapshot of snapshots) {
    const arr = snapshotsByAccount.get(snapshot.account_id as string) || [];
    arr.push(snapshot);
    snapshotsByAccount.set(snapshot.account_id as string, arr);
  }

  const overridesByCycle = new Map<string, Record<string, unknown>>();
  for (const row of cycleStartOverrides) {
    const key = `${row.account_id}:${String(row.statement_issue_date).slice(0, 10)}`;
    overridesByCycle.set(key, row);
  }

  const transactionsByAccount = new Map<string, Record<string, unknown>[]>();
  for (const transaction of transactions) {
    const accountId = transaction.account_id as string;
    if (accountId) {
      const arr = transactionsByAccount.get(accountId) || [];
      arr.push(transaction);
      transactionsByAccount.set(accountId, arr);
    }
  }

  const summaryRows: Record<string, unknown>[] = [];
  const now = new Date().toISOString();

  for (const account of accounts) {
    const accountId = account.account_id as string;
    const accountSnapshots = snapshotsByAccount.get(accountId) || [];
    if (accountSnapshots.length === 0) continue;

    const latest = accountSnapshots[accountSnapshots.length - 1]!;
    const currentIssueDate = statementIssueDate(latest.statement_issue_date);
    const prior = accountSnapshots.length > 1 ? accountSnapshots[accountSnapshots.length - 2] : null;
    let priorIssueDate = prior ? statementIssueDate(prior.statement_issue_date) : null;

    let cycleStartSource = "plaid";
    const manualOverride = overridesByCycle.get(`${accountId}:${String(latest.statement_issue_date).slice(0, 10)}`);

    if (!priorIssueDate && manualOverride) {
      priorIssueDate = statementIssueDate(manualOverride.cycle_start_date);
      cycleStartSource = "user_entered";
    }

    const base: Record<string, unknown> = {
      user_id: userId,
      account_id: accountId,
      statement_issue_date: latest.statement_issue_date,
      cycle_start_date: priorIssueDate ? priorIssueDate.toISOString().split("T")[0] : null,
      cycle_end_date: currentIssueDate ? currentIssueDate.toISOString().split("T")[0] : null,
      primary_person_id: primary.person_id,
      statement_balance: latest.statement_balance,
      updated_at: now,
    };

    if (!priorIssueDate) {
      summaryRows.push({
        ...base,
        status: "NEEDS_PRIOR_STATEMENT",
        amount_owed: null,
        primary_transaction_count: 0,
        excluded_transaction_count: 0,
        excluded_amount: 0,
        review_event_count: 0,
        details: {
          reason: "Enter the prior statement close date to define the complete cycle.",
        },
      });
      continue;
    }

    const priorIssueDateVal = priorIssueDate;
    const currentIssueDateVal = currentIssueDate!;

    let primaryTotal = new Decimal(0);
    let excludedTotal = new Decimal(0);
    let primaryCount = 0;
    let excludedCount = 0;
    const reviewTransactionIds = new Set<string>();

    for (const [eventId, reconciliation] of reconciliationByEvent) {
      if (!["AMBIGUOUS", "REVIEW", "PENDING"].includes(reconciliation.status as string)) continue;
      const event = eventsById.get(eventId);
      if (!event || event.person_id === null) continue;
      const eventDate = statementIssueDate(event.occurred_at);
      if (eventDate && priorIssueDateVal.getTime() < eventDate.getTime() && eventDate.getTime() <= currentIssueDateVal.getTime()) {
        const candidateId = reconciliation.candidate_transaction_id;
        if (candidateId) reviewTransactionIds.add(candidateId as string);
      }
    }

    const reviewEventIds = new Set<string>();
    for (const [eventId, event] of eventsById) {
      const eventDate = statementIssueDate(event.occurred_at);
      if (
        event.person_id &&
        eventDate &&
        priorIssueDateVal.getTime() < eventDate.getTime() &&
        eventDate.getTime() <= currentIssueDateVal.getTime()
      ) {
        const reconciliation = reconciliationByEvent.get(eventId);
        if (!reconciliation || !["HIGH", "MEDIUM"].includes(reconciliation.status as string)) {
          reviewEventIds.add(eventId);
        }
      }
    }

    let excludedNonChargeCount = 0;
    for (const transaction of transactionsByAccount.get(accountId) || []) {
      const txDate = statementIssueDate(transaction.date);
      if (
        !txDate ||
        !(priorIssueDateVal.getTime() < txDate.getTime() && txDate.getTime() <= currentIssueDateVal.getTime()) ||
        transaction.pending
      ) continue;

      const amount = new Decimal(String(transaction.amount));
      const txCode = String(transaction.transaction_code || "").toLowerCase();
      if (txCode === "payment" || amount.lte(0)) {
        excludedNonChargeCount += 1;
        continue;
      }

      const explicit = assignmentByTx.get(transaction.transaction_id as string);
      if (
        reviewTransactionIds.has(transaction.transaction_id as string) &&
        !(explicit && explicit.assignment_source === "manual")
      ) continue;

      const assignedPersonId = explicit ? explicit.person_id : primary.person_id;
      if (assignedPersonId === primary.person_id) {
        primaryTotal = primaryTotal.plus(amount);
        primaryCount += 1;
      } else if (peopleById.has(assignedPersonId as string)) {
        excludedTotal = excludedTotal.plus(amount);
        excludedCount += 1;
      }
    }

    const reviewCount = reviewEventIds.size + reviewTransactionIds.size;
    summaryRows.push({
      ...base,
      status: reviewCount > 0 ? "REVIEW" : "READY",
      amount_owed: Decimal.max(new Decimal(0), primaryTotal).toFixed(2),
      primary_transaction_count: primaryCount,
      excluded_transaction_count: excludedCount,
      excluded_amount: excludedTotal.toFixed(2),
      review_event_count: reviewCount,
      details: {
        unresolved_event_count: reviewEventIds.size,
        candidate_transaction_review_count: reviewTransactionIds.size,
        excluded_non_charge_count: excludedNonChargeCount,
        amounts_include_positive_posted_charges_only: true,
        cycle_start_source: cycleStartSource,
        primary_charge_total: primaryTotal.toFixed(2),
      },
    });
  }

  for (let i = 0; i < summaryRows.length; i += 500) {
    const batch = summaryRows.slice(i, i + 500);
    const { error } = await supabase
      .from("card_statement_summaries")
      .upsert(batch, { onConflict: "user_id,account_id,statement_issue_date" });
    if (error) throw new Error(`Could not save statement summaries: ${error.message}`);
  }

  return summaryRows.length;
}

export { fetchUserRows, statementIssueDate };

