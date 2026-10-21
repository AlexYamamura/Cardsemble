import { Decimal } from "https://esm.sh/decimal.js@10.4.3";
import { supabase } from "./supabase.ts";
import { getHouseholdPerson } from "./auth.ts";
import type { PlaidPublicTokenExchange } from "./types.ts";

export interface PlaidItemSyncError {
  item_id: string;
  institution_name: string | null;
  error_code: string | null;
  message: string;
}

export interface PlaidSyncResult {
  ok: true;
  items_synced: number;
  items_failed: number;
  item_errors: PlaidItemSyncError[];
  added: number;
  modified: number;
  removed: number;
  reconciled: number;
  wallet_assigned: number;
  liabilities: { status: string; accounts: number; statements: number };
  statement_summaries: number;
  user_id: string;
}

export interface PlaidExchangeResult extends PlaidSyncResult {
  item_id: string;
  institution_name: string;
}

const PLAID_BASE_URL =
  (Deno.env.get("PLAID_ENV") || "production").toLowerCase() === "sandbox"
    ? "https://sandbox.plaid.com"
    : "https://production.plaid.com";

async function plaidCall(endpoint: string, body: Record<string, unknown>): Promise<any> {
  const clientId = Deno.env.get("PLAID_CLIENT_ID");
  const secret = Deno.env.get("PLAID_SECRET");
  if (!clientId || !secret) {
    throw new Error("PLAID_CLIENT_ID and PLAID_SECRET must be set");
  }

  const response = await fetch(`${PLAID_BASE_URL}${endpoint}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ client_id: clientId, secret, ...body }),
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({}));
    const message = err.display_message || err.error_code || response.statusText;
    const error: Error & { code?: string } = new Error(`Plaid API error: ${message}`);
    error.code = err.error_code;
    throw error;
  }

  return response.json();
}

/// Extracts the Plaid `error_code` from an error thrown by `plaidCall`.
/// Returns null for errors that did not come from Plaid (database failures,
/// programming errors), which must stay fatal.
function plaidErrorCode(error: unknown): string | null {
  if (error instanceof Error) {
    const code = (error as Error & { code?: unknown }).code;
    if (typeof code === "string" && code.length > 0) return code;
  }
  return null;
}

/// Plaid error codes that mean the stored connection is dead and the user has
/// to sign in again. These mark the item as broken so it is not retried
/// forever.
const REAUTH_ERROR_CODES = new Set([
  "ITEM_LOGIN_REQUIRED",
  "INVALID_ACCESS_TOKEN",
  "REAUTH_REQUIRED",
  "INVALID_CREDENTIALS",
]);

/// Plaid error codes that describe a problem with the integration itself
/// (bad credentials, rejected requests) rather than with one connection.
/// These must fail the whole run instead of being reported per item.
const SYSTEMIC_PLAID_ERROR_CODES = new Set([
  "INVALID_API_KEYS",
  "INVALID_INPUT",
]);

function plaidItemSyncMessage(code: string): string {
  if (REAUTH_ERROR_CODES.has(code)) {
    return "This connection needs to be re-authenticated.";
  }
  return `Plaid reported an error for this connection (${code}).`;
}

export async function createPlaidClient(): Promise<void> {
  const env = (Deno.env.get("PLAID_ENV") || "production").toLowerCase();
  if (!["production", "sandbox"].includes(env)) {
    throw new Error("PLAID_ENV must be production or sandbox");
  }
  const required = ["PLAID_CLIENT_ID", "PLAID_SECRET"];
  for (const name of required) {
    if (!Deno.env.get(name)) {
      throw new Error(`Plaid API credentials are not configured`);
    }
  }
}

export async function createPlaidLinkToken(userId: string, platform: "android" | "ios" | "web"): Promise<string> {
  await createPlaidClient();

  const requestOptions: Record<string, unknown> = {
    user: { client_user_id: userId },
    client_name: "Cardsemble",
    country_codes: ["US"],
    language: "en",
    products: ["transactions"],
    optional_products: ["liabilities"],
  };

  if (platform === "android") {
    requestOptions["android_package_name"] = "com.plaidtest.cardsemble";
  }

  const redirectUri = Deno.env.get("PLAID_REDIRECT_URI");
  if (redirectUri) {
    requestOptions["redirect_uri"] = redirectUri;
  }

  const response = await plaidCall("/link/token/create", requestOptions);
  return response.link_token;
}

export async function createLiabilitiesLinkToken(userId: string): Promise<string> {
  await createPlaidClient();
  const accessToken = Deno.env.get("PLAID_ACCESS_TOKEN");
  if (!accessToken) {
    throw new Error("Plaid connection is not configured");
  }

  const response = await plaidCall("/link/token/create", {
    user: { client_user_id: userId },
    client_name: "Credit Cards",
    country_codes: ["US"],
    language: "en",
    access_token: accessToken,
    additional_consented_products: ["liabilities"],
  });

  return response.link_token;
}

export async function exchangePublicToken(
  payload: PlaidPublicTokenExchange,
  userId: string,
): Promise<PlaidExchangeResult> {
  await createPlaidClient();

  // A public token is single-use, so it must only be exchanged once.
  const exchange = await plaidCall("/item/public_token/exchange", {
    public_token: payload.public_token,
  });

  const itemResponse = await plaidCall("/item/get", {
    access_token: exchange.access_token,
  });

  const itemId = itemResponse.item.item_id;
  const institutionId = payload.institution_id || itemResponse.item.institution_id;
  const institutionName = payload.institution_name || "Linked institution";

  const { error: upsertError } = await supabase
    .from("plaid_items")
    .upsert({
      item_id: itemId,
      user_id: userId,
      access_token: exchange.access_token,
      institution_id: institutionId,
      institution_name: institutionName,
      status: "connected",
      updated_at: new Date().toISOString(),
    }, { onConflict: "item_id" });

  if (upsertError) {
    throw new Error("Plaid linked successfully, but its secure connection could not be saved");
  }

  const syncResult = await syncPlaidItemsForUser(userId);
  return {
    item_id: itemId,
    institution_name: institutionName,
    ...syncResult,
  };
}

async function syncPlaidTransactionPage(
  userId: string,
  added: any[],
  modified: any[],
  removed: any[],
): Promise<[number, number, number]> {
  const records: Record<string, unknown>[] = [];
  for (const transaction of [...added, ...modified]) {
    const location = (transaction as any).location;
    const category = (transaction as any).personal_finance_category;
    const counterparties = (transaction as any).counterparties;
    const paymentMeta = (transaction as any).payment_meta;

    records.push({
      transaction_id: transaction.transaction_id,
      account_id: transaction.account_id,
      amount: transaction.amount,
      iso_currency_code: transaction.iso_currency_code,
      date: transaction.date,
      authorized_date: transaction.authorized_date,
      datetime: transaction.datetime,
      authorized_datetime: transaction.authorized_datetime,
      name: transaction.name,
      original_description: transaction.original_description,
      merchant_name: transaction.merchant_name,
      merchant_entity_id: transaction.merchant_entity_id,
      website: transaction.website,
      merchant_category_code: transaction.merchant_category_code,
      payment_channel: transaction.payment_channel,
      location_address: location?.address,
      location_city: location?.city,
      location_region: location?.region,
      location_postal_code: location?.postal_code,
      location_country: location?.country,
      location_lat: location?.lat,
      location_lon: location?.lon,
      location_store_number: location?.store_number,
      personal_finance_category_primary: category?.primary,
      personal_finance_category_detailed: category?.detailed,
      personal_finance_category_confidence: category?.confidence_level,
      transaction_type: transaction.transaction_type,
      transaction_code: transaction.transaction_code,
      pending: Boolean(transaction.pending),
      pending_transaction_id: transaction.pending_transaction_id,
      counterparties: counterparties
        ? counterparties.map((e: any) => (e.to_dict ? e.to_dict() : e))
        : null,
      payment_meta: paymentMeta && paymentMeta.to_dict ? paymentMeta.to_dict() : paymentMeta,
      user_id: userId,
      is_removed: false,
      synced_at: new Date().toISOString(),
    });
  }

  if (records.length > 0) {
    const { error } = await supabase
      .from("plaid_transactions")
      .upsert(records, { onConflict: "transaction_id" });
    if (error) throw new Error(`Could not save transactions: ${error.message}`);
  }

  let removedCount = 0;
  for (const transaction of removed) {
    const transactionId = typeof transaction === "string" ? transaction : transaction.transaction_id;
    const { data, error } = await supabase
      .from("plaid_transactions")
      .update({
        is_removed: true,
        synced_at: new Date().toISOString(),
      })
      .eq("transaction_id", transactionId)
      .eq("user_id", userId)
      .select("transaction_id");

    if (error) throw new Error(`Could not remove transaction: ${error.message}`);
    removedCount += data?.length ?? 0;
  }

  return [added.length, modified.length, removedCount];
}

export async function savePlaidCreditAccounts(
  accounts: any[],
  userId: string,
  itemId: string,
  institutionName: string | null,
): Promise<number> {
  const { data: existingAccounts, error: fetchError } = await supabase
    .from("plaid_credit_accounts")
    .select("account_id,display_name")
    .eq("user_id", userId);

  if (fetchError) throw new Error(`Could not fetch credit accounts: ${fetchError.message}`);

  const existingDisplayNames = new Map(
    (existingAccounts ?? []).map((row) => [row.account_id, row.display_name]),
  );

  const accountRows: any[] = [];
  for (const account of accounts) {
    const accountType = typeof account.type === "object" ? account.type.value : account.type;
    if (accountType !== "credit") continue;

    const officialName = account.official_name ?? null;
    const name = account.name;
    let displayName = existingDisplayNames.get(account.account_id);
    if (!displayName) {
      displayName = mappedPlaidCreditCardName(officialName, name);
    }

    const balances = account.balances;
    accountRows.push({
      account_id: account.account_id,
      item_id: itemId,
      user_id: userId,
      name: name,
      official_name: officialName,
      display_name: displayName,
      mask: account.mask,
      account_type: accountType,
      subtype: account.subtype ? (typeof account.subtype === "object" ? account.subtype.value : account.subtype) : null,
      iso_currency_code: balances?.iso_currency_code ?? null,
      institution_name: institutionName,
      updated_at: new Date().toISOString(),
    });
  }

  for (let i = 0; i < accountRows.length; i += 500) {
    const batch = accountRows.slice(i, i + 500);
    const { error } = await supabase
      .from("plaid_credit_accounts")
      .upsert(batch, { onConflict: "account_id" });
    if (error) throw new Error(`Could not save credit accounts: ${error.message}`);
  }

  return accountRows.length;
}

export async function syncPlaidCreditAccounts(
  accessToken: string,
  userId: string,
  itemId: string,
  institutionName: string | null,
): Promise<number> {
  const response = await plaidCall("/accounts/get", {
    access_token: accessToken,
  });
  return savePlaidCreditAccounts(response.accounts, userId, itemId, institutionName);
}

export async function syncPlaidLiabilities(
  accessToken: string,
  userId: string,
  itemId?: string,
  institutionName?: string,
): Promise<{ status: string; accounts: number; statements: number }> {
  let response: any;
  try {
    response = await plaidCall("/liabilities/get", {
      access_token: accessToken,
    });
  } catch (error: any) {
    const code = error.code || "LIABILITIES_UNAVAILABLE";
    const result = { status: "unavailable", reason: code, accounts: 0, statements: 0 };
    const { error: upsertError } = await supabase
      .from("plaid_liability_sync_state")
      .upsert({
        user_id: userId,
        status: result.status,
        account_count: result.accounts,
        statement_count: result.statements,
        reason: code,
        updated_at: new Date().toISOString(),
      }, { onConflict: "user_id" });
    if (upsertError) throw new Error(`Could not save liability sync state: ${upsertError.message}`);
    return result;
  }

  const accountRows = (response.accounts ?? [])
    .filter((account: any) => {
      const accountType = typeof account.type === "object" ? account.type.value : account.type;
      return accountType === "credit";
    })
    .map((account: any) => ({
      account_id: account.account_id,
      iso_currency_code: account.balances?.iso_currency_code ?? null,
    }));

  if (itemId) {
    await savePlaidCreditAccounts(response.accounts, userId, itemId, institutionName);
  }

  const accountsById = new Map(accountRows.map((row: any) => [row.account_id, row]));
  const now = new Date().toISOString();
  const snapshots: any[] = [];

  const creditLiabilities = response.liabilities?.credit ?? [];
  for (const liability of creditLiabilities) {
    const accountId = liability.account_id;
    const account = accountsById.get(accountId);
    const issueDate = liability.last_statement_issue_date;
    if (!account || !issueDate) continue;

    snapshots.push({
      user_id: userId,
      account_id: accountId,
      statement_issue_date: issueDate,
      statement_balance: liability.last_statement_balance,
      minimum_payment_amount: liability.minimum_payment_amount,
      next_payment_due_date: liability.next_payment_due_date ?? null,
      iso_currency_code: account.iso_currency_code,
      fetched_at: now,
    });
  }

  if (snapshots.length > 0) {
    const { error } = await supabase
      .from("plaid_liability_snapshots")
      .upsert(snapshots, { onConflict: "user_id,account_id,statement_issue_date" });
    if (error) throw new Error(`Could not save liability snapshots: ${error.message}`);
  }

  const result = {
    status: "synced",
    accounts: accountRows.length,
    statements: snapshots.length,
  };

  const { error: syncStateError } = await supabase
    .from("plaid_liability_sync_state")
    .upsert({
      user_id: userId,
      status: result.status,
      reason: null,
      account_count: result.accounts,
      statement_count: result.statements,
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id" });
  if (syncStateError) throw new Error(`Could not save liability sync state: ${syncStateError.message}`);

  return result;
}

async function resolveInstitutionName(client: any, institutionId: string | null): Promise<string | null> {
  if (!institutionId) return null;
  try {
    const response = await plaidCall("/institutions/get_by_id", {
      institution_id: institutionId,
      country_codes: ["US"],
    });
    if (response.institution && response.institution.name) {
      return response.institution.name;
    }
  } catch {
    console.warn(`Could not resolve institution name for ${institutionId}`);
  }
  return null;
}

export async function syncPlaidItemsForUser(userId: string): Promise<PlaidSyncResult> {
  await createPlaidClient();

  const { data: items, error: itemsError } = await supabase
    .from("plaid_items")
    .select("*")
    .eq("user_id", userId)
    .order("created_at", { ascending: true })
    .order("item_id", { ascending: true });

  if (itemsError) throw new Error(`Could not fetch Plaid items: ${itemsError.message}`);

  const connectedItems = (items ?? []).filter((item) => item.status === "connected");
  const legacyAccessToken = Deno.env.get("PLAID_ACCESS_TOKEN");
  const legacyUserId = Deno.env.get("PLAID_USER_ID");

  if (
    legacyAccessToken &&
    legacyUserId &&
    legacyUserId === userId &&
    !connectedItems.some((item) => item.access_token === legacyAccessToken)
  ) {
    try {
      const itemResponse = await plaidCall("/item/get", {
        access_token: legacyAccessToken,
      });
      const legacyItem = itemResponse.item;
      const itemId = legacyItem.item_id;
      const existing = connectedItems.find((item) => item.item_id === itemId);

      if (!existing) {
        const instName = (await resolveInstitutionName(null, legacyItem.institution_id)) || "Chase";
        const { error: insertError } = await supabase
          .from("plaid_items")
          .upsert({
            item_id: itemId,
            user_id: userId,
            access_token: legacyAccessToken,
            institution_id: legacyItem.institution_id,
            institution_name: instName,
            status: "connected",
            updated_at: new Date().toISOString(),
          }, { onConflict: "item_id" });

        if (insertError) throw new Error("Could not save the existing Plaid connection");
        connectedItems.push({
          item_id: itemId,
          access_token: legacyAccessToken,
          institution_id: legacyItem.institution_id,
          institution_name: instName,
          status: "connected",
          updated_at: new Date().toISOString(),
        });
      }
    } catch (error: any) {
      if (error.message?.includes("Could not save the existing Plaid connection")) {
        throw error;
      }
      throw new Error("Could not migrate the existing Plaid connection");
    }
  }

  const itemErrors: PlaidItemSyncError[] = [];
  for (const item of (items ?? []) as any[]) {
    const status = item?.status;
    if (status === "connected" || status === "disconnected") continue;
    itemErrors.push({
      item_id: item?.item_id ?? "",
      institution_name: item?.institution_name ?? null,
      error_code: "ITEM_LOGIN_REQUIRED",
      message: "This connection needs to be re-authenticated.",
    });
  }

  // An account can hold only stale items, in which case there is nothing to
  // sync but there is still something to report. An account with no usable
  // connection at all (no connected items and no stale ones) is still an
  // error, so the caller is not told that a sync succeeded when nothing ran.
  if (connectedItems.length === 0 && itemErrors.length === 0) {
    throw new Error("No Plaid connections are available to sync");
  }

  let addedCount = 0;
  let modifiedCount = 0;
  let removedCount = 0;
  let liabilityAccountCount = 0;
  let liabilityStatementCount = 0;
  let liabilityFailures = 0;
  let itemsSynced = 0;

  for (const item of connectedItems) {
    // A single stale item (for example one that needs re-authentication) must
    // not abort the whole sync. Plaid-reported failures are isolated and
    // reported back to the client; anything else stays fatal.
    try {
      let instName = item.institution_name;
      if ((!instName || isGenericCardName(instName)) && item.institution_id) {
        const resolved = await resolveInstitutionName(null, item.institution_id);
        if (resolved) {
          instName = resolved;
          item.institution_name = resolved;
          await supabase
            .from("plaid_items")
            .update({ institution_name: resolved })
            .eq("item_id", item.item_id);

          await supabase
            .from("plaid_credit_accounts")
            .update({ institution_name: resolved })
            .eq("item_id", item.item_id)
            .in("institution_name", ["Existing linked institution", "Linked institution"]);
        }
      }

      let cursor: string | null = item.transactions_cursor ?? null;

      while (true) {
        const requestOptions: Record<string, unknown> = {
          access_token: item.access_token,
          options: { include_original_description: true },
        };
        if (cursor) {
          requestOptions["cursor"] = cursor;
        }

        const response = await plaidCall("/transactions/sync", requestOptions);
        const [savedAdded, savedModified, savedRemoved] = await syncPlaidTransactionPage(
          userId,
          response.added ?? [],
          response.modified ?? [],
          response.removed ?? [],
        );
        addedCount += savedAdded;
        modifiedCount += savedModified;
        removedCount += savedRemoved;
        cursor = response.next_cursor;
        if (!response.has_more) break;
      }

      await supabase
        .from("plaid_items")
        .update({
          transactions_cursor: cursor,
          updated_at: new Date().toISOString(),
        })
        .eq("item_id", item.item_id)
        .eq("user_id", userId);

      await syncPlaidCreditAccounts(
        item.access_token,
        userId,
        item.item_id,
        item.institution_name,
      );

      const liabilities = await syncPlaidLiabilities(
        item.access_token,
        userId,
        item.item_id,
        item.institution_name,
      );
      liabilityAccountCount += liabilities.accounts;
      liabilityStatementCount += liabilities.statements;
      if (liabilities.status !== "synced") {
        liabilityFailures += 1;
      }

      itemsSynced += 1;
    } catch (error: unknown) {
      const code = plaidErrorCode(error);
      if (!code) throw error;
      if (SYSTEMIC_PLAID_ERROR_CODES.has(code)) {
        // A broken credential or a rejected request is a deployment problem,
        // not a problem with this one connection. It must stay fatal.
        throw error;
      }

      itemErrors.push({
        item_id: item.item_id,
        institution_name: item.institution_name ?? null,
        error_code: code,
        message: plaidItemSyncMessage(code),
      });

      if (REAUTH_ERROR_CODES.has(code)) {
        // "error" is the only status the schema allows for a broken item.
        const { error: statusError } = await supabase
          .from("plaid_items")
          .update({
            status: "error",
            updated_at: new Date().toISOString(),
          })
          .eq("item_id", item.item_id)
          .eq("user_id", userId);
        if (statusError) {
          console.warn(
            `Could not mark Plaid item ${item.item_id} as needing re-authentication: ${statusError.message}`,
          );
        }
      }
    }
  }

  const liabilityStatus =
    itemsSynced === 0
      ? "unavailable"
      : liabilityStatementCount > 0 || !liabilityFailures
        ? "synced"
        : "unavailable";

  const { error: syncStateError } = await supabase
    .from("plaid_liability_sync_state")
    .upsert({
      user_id: userId,
      status: liabilityStatus,
      reason: liabilityStatus === "unavailable" ? "LIABILITIES_UNAVAILABLE" : null,
      account_count: liabilityAccountCount,
      statement_count: liabilityStatementCount,
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id" });

  if (syncStateError) throw new Error(`Could not save liability sync state: ${syncStateError.message}`);

  const reconciledCount = await import("./reconcile.ts").then((m) => m.reconcileUserCardEvents(userId));
  const assignedCount = await import("./reconcile.ts").then((m) => m.refreshWalletAssignments(userId));
  const summaryCount = await import("./reconcile.ts").then((m) => m.calculateStatementSummaries(userId));

  return {
    ok: true,
    items_synced: itemsSynced,
    items_failed: itemErrors.length,
    item_errors: itemErrors,
    added: addedCount,
    modified: modifiedCount,
    removed: removedCount,
    reconciled: reconciledCount,
    wallet_assigned: assignedCount,
    liabilities: {
      status: liabilityStatus,
      accounts: liabilityAccountCount,
      statements: liabilityStatementCount,
    },
    statement_summaries: summaryCount,
    user_id: userId,
  };
}

export async function runPlaidSync(): Promise<PlaidSyncResult> {
  const userId = Deno.env.get("PLAID_USER_ID");
  if (!userId) {
    throw new Error("Plaid scheduled sync is missing required configuration");
  }
  return syncPlaidItemsForUser(userId);
}

function isGenericCardName(val: string | null | undefined): boolean {
  if (!val || typeof val !== "string") return true;
  const GENERIC = new Set([
    "credit card", "credit", "card",
    "existing linked institution", "linked institution", "unknown",
  ]);
  return GENERIC.has(val.trim().toLowerCase());
}

function mappedPlaidCreditCardName(officialName: string | null, name: string | null): string | null {
  const PLAID_CREDIT_CARD_NAME_MAPPINGS: Record<string, string> = {
    "ultimaterewards": "Chase Freedom Unlimited",
  };
  for (const sourceName of [officialName, name]) {
    if (!sourceName) continue;
    const key = sourceName.toLowerCase().replace(/[^a-z0-9]/g, "");
    const mapped = PLAID_CREDIT_CARD_NAME_MAPPINGS[key];
    if (mapped) return mapped;
  }
  return null;
}
