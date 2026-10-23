import { supabase } from "../_shared/supabase.ts";
import {
  getBearerToken,
  authenticateRequest,
  verifySupabaseUser,
  ensureDefaultPerson,
  getHouseholdPerson,
  ApiError,
} from "../_shared/auth.ts";
import {
  createPlaidLinkToken,
  createLiabilitiesLinkToken,
  exchangePublicToken,
  syncPlaidItemsForUser,
  syncPlaidItemForUser,
  runPlaidSync,
} from "../_shared/plaid.ts";
import {
  reconcileUserCardEvents,
  refreshWalletAssignments,
  calculateStatementSummaries,
  fetchUserRows,
  creditCardDisplayName,
} from "../_shared/reconcile.ts";
import {
  generateCsvPreview,
  confirmCsvImport,
} from "../_shared/csv_import.ts";
import {
  syncCardCatalog,
} from "../_shared/card_catalog.ts";
import { Decimal } from "https://esm.sh/decimal.js@10.4.3";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function errorResponse(error: unknown): Response {
  if (error instanceof ApiError) {
    return jsonResponse({ detail: error.message }, error.statusCode);
  }
  if (error instanceof Error) {
    const codeMatch = error.message.match(/^(\d+):\s/);
    if (codeMatch) {
      return jsonResponse({ detail: error.message.slice(codeMatch[0].length) }, parseInt(codeMatch[1], 10));
    }
    return jsonResponse({ detail: error.message }, 500);
  }
  return jsonResponse({ detail: "Internal server error" }, 500);
}

async function fetchAllRows(
  table: string,
  userId: string | null,
  params: Record<string, string>,
  selectOverride?: string,
): Promise<any[]> {
  const rows: any[] = [];
  let offset = 0;
  while (true) {
    const filters: Record<string, string> = {
      select: selectOverride || "*",
      limit: "500",
      offset: String(offset),
      ...params,
    };
    if (userId) {
      filters["user_id"] = `eq.${userId}`;
    } else {
      filters["user_id"] = "is.null";
    }

    const query = new URLSearchParams(filters as any).toString();
    const url = `${Deno.env.get("SUPABASE_URL")}/rest/v1/${table}?${query}`;
    const res = await fetch(url, {
      headers: {
        apikey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
        Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!}`,
      },
    });
    const data = await res.json();
    if (!res.ok) {
      return jsonResponse({ detail: (data as any)?.message || "Database error" }, 502);
    }
    if (!Array.isArray(data)) {
      return jsonResponse({ detail: `Unexpected response type ${typeof data}` }, 502);
    }
    rows.push(...data);
    if (data.length < 500) return rows;
    offset += data.length;
  }
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  let path = url.pathname;
  path = path.replace(/^\/functions\/v1\/[^/]+/, "");
  path = path.replace(/^\/api\/?/, "");
  path = path.replace(/^api\/?/, "");
  path = path.replace(/^\/+/, "").replace(/\/+$/, "");
  const method = req.method;
  const authorization = req.headers.get("Authorization");

  try {
    // --- Health check ---
  if (path === "" || path === "/" || path === "health") {
    return jsonResponse({ ok: true, service: "card-events-api" });
  }

     // --- Public config ---
     if (method === "GET" && path === "public-config") {
       const projectUrl = Deno.env.get("SUPABASE_URL");
       const publishableKey = Deno.env.get("SUPABASE_ANON_KEY");
       if (!projectUrl || !publishableKey) {
         throw new ApiError(503, "Supabase public client configuration is not configured");
       }
       return jsonResponse({ supabase_url: projectUrl, supabase_publishable_key: publishableKey });
     }

      // --- Card catalog (public) ---
      if (method === "GET" && path === "card-catalog") {
        const idsParam = url.searchParams.get("ids");
        const ids = idsParam ? idsParam.split(",").map(id => id.trim()).filter(Boolean) : [];
        
        let query = supabase.from("card_catalog").select("data");
        
        if (ids.length > 0) {
          query = query.in("id", ids);
        }
        // If no IDs specified, we return all cards (no additional filtering)

        const { data, error } = await query;

        if (error) {
          throw new ApiError(502, error.message);
        }

        // data is an array of { data: ... }
        const cards = data.map(row => row.data);
        return jsonResponse({ cards });
      }

    // --- Card events ---
    if (method === "POST" && path === "card-events") {
      const auth = await authenticateRequest(authorization);
      let userId = auth.userId;
      const authSource = auth.authSource;

      const body = await req.json();
      if (body.occurred_at && !body.occurred_at.includes("T") || (body.occurred_at && !body.occurred_at.includes("+"))) {
        // Validate timezone
        const d = new Date(body.occurred_at);
        if (isNaN(d.getTime()) || (d.getTimezoneOffset() === 0 && !body.occurred_at.endsWith("Z") && !body.occurred_at.includes("+"))) {
          throw new ApiError(422, "occurred_at must include a timezone");
        }
      }

      let personId: string | null = null;
      let deviceTokenId: string | null = null;
      let eventSource: string;

      if (authSource === "test_api_token") {
        eventSource = "api_test";
      } else {
        eventSource = authSource === "device_token" ? "ios_shortcut" : "authenticated_api";
      }

      if (userId && authSource === "device_token") {
        const token = getBearerToken(authorization);
        const hashBuffer = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
        const tokenHash = Array.from(new Uint8Array(hashBuffer)).map((b) => b.toString(16).padStart(2, "0")).join("");

        const { data: tokenRows, error } = await supabase
          .from("device_tokens")
          .select("id,person_id,platform")
          .eq("token_hash", tokenHash)
          .eq("user_id", userId)
          .is("revoked_at", null)
          .limit(1);

        if (error) throw new ApiError(502, error.message);
        if (tokenRows && tokenRows.length > 0) {
          personId = tokenRows[0].person_id;
          deviceTokenId = tokenRows[0].id;
          eventSource = tokenRows[0].platform || "ios_shortcut";
        }
      } else if (userId) {
        personId = (await ensureDefaultPerson(userId)).person_id;
      }

      const occurredAt = new Date(body.occurred_at);
      const utcString = occurredAt.toISOString();

      const { data: rows, error } = await supabase
        .from("card_events")
        .upsert({
          ...body,
          occurred_at: utcString,
          user_id: userId,
          person_id: personId,
          device_token_id: deviceTokenId,
          source: eventSource,
        }, { onConflict: "event_id" })
        .select();

      if (error) throw new ApiError(502, error.message);

      return jsonResponse({
        ok: true,
        saved: rows && rows.length > 0,
        event_id: rows && rows.length > 0 ? rows[0].event_id : body.event_id,
        user_id: userId,
        person_id: personId,
      });
    }

    if (method === "GET" && path === "card-events") {
      const auth = await authenticateRequest(authorization);
      const limit = Math.min(parseInt(url.searchParams.get("limit") || "100", 10), 500);
      const offset = parseInt(url.searchParams.get("offset") || "0", 10);

      let query = supabase
        .from("card_events")
        .select("event_id,user_id,person_id,occurred_at,amount,currency,merchant,card_label,payment_label,source,received_at", { count: "exact" });

      if (auth.userId) {
        query = query.eq("user_id", auth.userId);
      } else {
        query = query.is("user_id", null);
      }

      const { data, error, count } = await query
        .order("received_at", { ascending: false })
        .order("event_id", { ascending: true })
        .range(offset, offset + limit - 1);

      if (error) throw new ApiError(502, error.message);
      const events = (data ?? []).map((row: any) => ({
        ...row,
        user_id: auth.userId,
      }));

      return jsonResponse({ events });
    }

    // --- Household people ---
    if (method === "GET" && path === "household/people") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      await ensureDefaultPerson(auth.userId);
      const people = await fetchUserRows("household_people", auth.userId, { orderBy: "created_at.asc,person_id.asc" });
      return jsonResponse({ people });
    }

    if (method === "POST" && path === "household/people") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const body = await req.json().catch(() => ({}));
      const displayName = (body.display_name || "").trim();
      if (!displayName || displayName.length > 100) {
        throw new ApiError(400, "Invalid display_name");
      }
      await ensureDefaultPerson(auth.userId);
      const { data, error } = await supabase
        .from("household_people")
        .insert({ user_id: auth.userId, display_name: displayName, is_default: false })
        .select();
      if (error) throw new ApiError(502, error.message);
      return jsonResponse({ person: data?.[0] });
    }

    if (method === "PATCH" && path.startsWith("household/people/")) {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const personId = path.split("/")[2];
      if (!personId) {
        throw new ApiError(400, "Invalid person ID");
      }
      const body = await req.json().catch(() => ({}));
      const displayName = body.display_name ? String(body.display_name).trim() : null;
      const isDefault = body.is_default;

      // Validate input
      if (displayName === null && isDefault === null) {
        throw new ApiError(400, "At least one of display_name or is_default must be provided");
      }
      if (displayName !== null && (displayName.length === 0 || displayName.length > 100)) {
        throw new ApiError(400, "Invalid display_name");
      }

      await ensureDefaultPerson(auth.userId); // Ensure a default person exists

      // If setting as default, ensure we don't create multiple defaults
      if (isDefault === true) {
        // First, unset any existing default for this user
        await supabase
          .from("household_people")
          .update({ is_default: false })
          .eq("user_id", auth.userId);
      }

      const updateData: any = {};
      if (displayName !== null) {
        updateData.display_name = displayName;
      }
      if (isDefault !== null) {
        updateData.is_default = isDefault;
      }

      const { data, error } = await supabase
        .from("household_people")
        .update(updateData)
        .eq("person_id", personId)
        .eq("user_id", auth.userId)
        .select();

      if (error) throw new ApiError(502, error.message);
      if (!data || data.length === 0) throw new ApiError(404, "Household person not found");
      return jsonResponse({ person: data?.[0] });
    }

    // --- Device tokens ---
    if (method === "POST" && path === "device-tokens") {
      const bearerToken = getBearerToken(authorization);
      const userId = await verifySupabaseUser(bearerToken);
      const body = await req.json().catch(() => ({}));

      const deviceLabel = (body.device_label || "").trim();
      if (!deviceLabel || deviceLabel.length > 100) {
        throw new ApiError(400, "Invalid device_label");
      }
      const personId = body.person_id ? String(body.person_id) : (await ensureDefaultPerson(userId)).person_id;
      const person = await getHouseholdPerson(userId, personId);
      if (!person) throw new ApiError(404, "Household member not found");

      const platform = body.platform || "ios_shortcut";
      const tokenChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-";
      let deviceToken = "";
      const arr = new Uint8Array(32);
      crypto.getRandomValues(arr);
      for (const byte of arr) {
        deviceToken += tokenChars[byte % tokenChars.length];
      }

      const hashBuffer = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(deviceToken));
      const tokenHash = Array.from(new Uint8Array(hashBuffer)).map((b) => b.toString(16).padStart(2, "0")).join("");

      const { data: rows, error } = await supabase
        .from("device_tokens")
        .insert({
          user_id: userId,
          person_id: personId,
          device_label: deviceLabel,
          platform: platform,
          token_hash: tokenHash,
        })
        .select();

      if (error) throw new ApiError(502, error.message);
      return jsonResponse({
        device_token: deviceToken,
        id: rows![0].id,
        device_label: deviceLabel,
        person_id: personId,
        warning: "Copy this token now; it cannot be retrieved later.",
      });
    }

    if (method === "GET" && path === "device-tokens") {
      const bearerToken = getBearerToken(authorization);
      const userId = await verifySupabaseUser(bearerToken);
      const { data, error } = await supabase
        .from("device_tokens")
        .select("id,device_label,person_id,created_at,last_used_at,revoked_at")
        .eq("user_id", userId)
        .order("created_at", { ascending: false });
      if (error) throw new ApiError(502, error.message);
      return jsonResponse({ devices: data ?? [] });
    }

    if (method === "DELETE" && path.startsWith("device-tokens/")) {
      const bearerToken = getBearerToken(authorization);
      const userId = await verifySupabaseUser(bearerToken);
      const tokenId = path.split("/")[1];
      const { data, error } = await supabase
        .from("device_tokens")
        .update({ revoked_at: new Date().toISOString() })
        .eq("id", tokenId)
        .eq("user_id", userId)
        .is("revoked_at", null)
        .select();
      if (error) throw new ApiError(502, error.message);
      if (!data || data.length === 0) throw new ApiError(404, "Active device key not found");
      const uuid = tokenId;
      return jsonResponse({ ok: true, revoked: true, id: uuid });
    }

    if (method === "PATCH" && path.match(/^device-tokens\/[^\/]+\/person$/)) {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) throw new ApiError(403, "A signed-in user is required");
      const parts = path.split("/");
      const tokenId = parts[1];
      const body = await req.json().catch(() => ({}));
      const personId = String(body.person_id);

      const person = await getHouseholdPerson(auth.userId, personId);
      if (!person) throw new ApiError(404, "Household member not found");

      const { data: rows, error } = await supabase
        .from("device_tokens")
        .update({ person_id: personId })
        .eq("id", tokenId)
        .eq("user_id", auth.userId)
        .is("revoked_at", null)
        .select();
      if (error) throw new ApiError(502, error.message);
      if (!rows || rows.length === 0) throw new ApiError(404, "Active device key not found");

      await supabase
        .from("card_events")
        .update({ person_id: personId })
        .eq("device_token_id", tokenId)
        .eq("user_id", auth.userId);

      await refreshWalletAssignments(auth.userId);
      await calculateStatementSummaries(auth.userId);
      return jsonResponse({ ok: true, device_id: tokenId, person_id: personId });
    }

    // --- Plaid items ---
    if (method === "GET" && path === "plaid/items") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const items = await fetchUserRows("plaid_items", auth.userId, { orderBy: "created_at.asc,item_id.asc" });
      return jsonResponse({
        items: items
          .filter((item) => item.status !== "disconnected")
          .map((item) => ({
            item_id: item.item_id,
            institution_id: item.institution_id,
            institution_name: item.institution_name,
            status: item.status,
            created_at: item.created_at,
          })),
      });
    }

    if (method === "POST" && path === "plaid/items/link-token") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A Supabase session is required to link a bank");
      }
      const platform = (url.searchParams.get("platform") || "web") as "android" | "ios" | "web";
      const itemId = url.searchParams.get("item_id");
      let accessToken: string | undefined;

      if (itemId) {
        // Update mode: look up the item's access token so Plaid Link can
        // re-authenticate without creating a new item.
        const { data: itemRows, error: itemError } = await supabase
          .from("plaid_items")
          .select("access_token")
          .eq("item_id", itemId)
          .eq("user_id", auth.userId)
          .single();

        if (itemError || !itemRows?.access_token) {
          throw new ApiError(404, `Plaid item ${itemId} not found`);
        }
        accessToken = itemRows.access_token;
      }

      const linkToken = await createPlaidLinkToken(auth.userId, platform, accessToken);
      return jsonResponse({ link_token: linkToken });
    }

    if (method === "POST" && path === "plaid/items/exchange") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A Supabase session is required to link a bank");
      }
      const body = await req.json();
      const result = await exchangePublicToken(body, auth.userId);
      return jsonResponse(result);
    }

    if (method === "POST" && path === "plaid/items/sync") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const itemId = url.searchParams.get("item_id");
      const result = itemId
        ? await syncPlaidItemForUser(auth.userId, itemId)
        : await syncPlaidItemsForUser(auth.userId);
      return jsonResponse(result);
    }

    if (method === "POST" && path === "plaid-transactions/sync-now") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const configuredUserId = Deno.env.get("PLAID_USER_ID");
      if (!configuredUserId || configuredUserId !== auth.userId) {
        throw new ApiError(403, "This account is not configured for Plaid sync");
      }
      const result = await syncPlaidItemsForUser(auth.userId);
      return jsonResponse(result);
    }

    if (method === "POST" && path === "plaid/liabilities/link-token") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A Supabase session is required to link a bank");
      }
      const configuredUserId = Deno.env.get("PLAID_USER_ID");
      const accessToken = Deno.env.get("PLAID_ACCESS_TOKEN");
      if (!configuredUserId || configuredUserId !== auth.userId || !accessToken) {
        throw new ApiError(403, "This account is not configured for Plaid");
      }
      const linkToken = await createLiabilitiesLinkToken(auth.userId);
      return jsonResponse({ link_token: linkToken });
    }

    // --- Cron sync ---
    if ((method === "GET" || method === "POST") && path === "cron/plaid-sync") {
      const cronSecret = Deno.env.get("CRON_SECRET");
      if (!cronSecret) throw new ApiError(503, "Scheduled sync is not configured");

      let supplied: string | null = null;
      try {
        supplied = getBearerToken(authorization);
      } catch {
        throw new ApiError(401, "Unauthorized cron request");
      }
      if (supplied !== cronSecret) {
        throw new ApiError(401, "Unauthorized cron request");
      }

      const result = await runPlaidSync();
      return jsonResponse(result);
    }

    // --- Plaid transactions ---
    if (method === "POST" && path === "plaid-transactions/sync") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const body = await req.json();
      const added = body.added ?? [];
      const modified = body.modified ?? [];
      const removed = body.removed ?? [];

      const rows = [...added, ...modified].map((tx: any) => ({
        ...tx,
        user_id: auth.userId,
        is_removed: false,
        synced_at: new Date().toISOString(),
      }));

      if (rows.length > 0) {
        const { error: upsertError } = await supabase
          .from("plaid_transactions")
          .upsert(rows, { onConflict: "transaction_id" });
        if (upsertError) throw new ApiError(502, upsertError.message);
      }

      let removedCount = 0;
      for (const transactionId of removed) {
        const { data, error } = await supabase
          .from("plaid_transactions")
          .update({ is_removed: true, synced_at: new Date().toISOString() })
          .eq("transaction_id", transactionId)
          .eq("user_id", auth.userId)
          .select("transaction_id");
        if (error) throw new ApiError(502, error.message);
        removedCount += data?.length ?? 0;
      }

      return jsonResponse({ ok: true, saved: rows.length, removed: removedCount, user_id: auth.userId });
    }

    if (method === "GET" && path === "plaid-transactions") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const limit = Math.min(parseInt(url.searchParams.get("limit") || "500", 10), 500);
      const offset = parseInt(url.searchParams.get("offset") || "0", 10);
      const accountIdFilter = url.searchParams.get("account_id");
      const dateFrom = url.searchParams.get("date_from");
      const dateTo = url.searchParams.get("date_to");
      const householdVisibleParam = url.searchParams.get("household_visible");

      const creditAccounts = await fetchUserRows("plaid_credit_accounts", auth.userId, { orderBy: "account_id.asc" });
      const creditAccountIds = creditAccounts.filter((a) => a.account_id).map((a) => a.account_id);
      if (creditAccountIds.length === 0) {
        return jsonResponse({ transactions: [], has_more: false });
      }
      // An explicit account filter that the user does not own must never widen the query.
      if (accountIdFilter && !creditAccountIds.includes(accountIdFilter)) {
        return jsonResponse({ transactions: [], has_more: false });
      }

      // Only project the columns the client consumes; avoid the large JSON columns
      // (location, counterparties, payment_meta, category icon, ...) that were
      // previously pulled with select("*").
      let pageQuery = supabase
        .from("plaid_transactions")
        .select("transaction_id,account_id,amount,iso_currency_code,date,name,merchant_name,pending,transaction_code,household_visible")
        .eq("user_id", auth.userId)
        .eq("is_removed", false)
        .in("account_id", accountIdFilter ? [accountIdFilter] : creditAccountIds);

      if (dateFrom) pageQuery = pageQuery.gte("date", dateFrom);
      if (dateTo) pageQuery = pageQuery.lte("date", dateTo);
      if (householdVisibleParam === "true" || householdVisibleParam === "false") {
        pageQuery = pageQuery.eq("household_visible", householdVisibleParam === "true");
      }

      const { data: transactions, error: txError } = await pageQuery
        .order("date", { ascending: false })
        .order("transaction_id", { ascending: true })
        .range(offset, offset + limit - 1);
      if (txError) throw new ApiError(502, txError.message);

      const pageRows = transactions ?? [];
      const pageIds = pageRows.map((tx: any) => tx.transaction_id).filter(Boolean);

      // Scope assignment lookups to the current page instead of refetching the
      // entire assignment table on every 500-row page.
      const assignmentById = new Map<string, any>();
      const splitCounts = new Map<string, number>();
      if (pageIds.length > 0) {
        const { data: assignments, error: assignmentError } = await supabase
          .from("transaction_assignments")
          .select("transaction_id,person_id,assignment_source,amount")
          .eq("user_id", auth.userId)
          .in("transaction_id", pageIds);
        if (assignmentError) throw new ApiError(502, assignmentError.message);
        for (const assignment of assignments ?? []) {
          assignmentById.set(assignment.transaction_id, assignment);
          splitCounts.set(assignment.transaction_id, (splitCounts.get(assignment.transaction_id) ?? 0) + 1);
        }
      }

      const creditAccountById = new Map(creditAccounts.map((a) => [a.account_id, a]));
      const primary = await ensureDefaultPerson(auth.userId);

      const result = pageRows.map((tx: any) => ({
        ...tx,
        household_visible: tx.household_visible !== false,
        account_name: creditCardDisplayName(creditAccountById.get(tx.account_id) ?? {}),
        display_name: creditAccountById.get(tx.account_id)?.display_name ?? null,
        plaid_name: creditAccountById.get(tx.account_id)?.name ?? null,
        official_name: creditAccountById.get(tx.account_id)?.official_name ?? null,
        account_mask: creditAccountById.get(tx.account_id)?.mask ?? null,
        assigned_person_id: assignmentById.has(tx.transaction_id)
          ? assignmentById.get(tx.transaction_id)!.person_id
          : primary.person_id,
        assignment_source: assignmentById.has(tx.transaction_id)
          ? assignmentById.get(tx.transaction_id)!.assignment_source
          : "default",
        has_splits: (splitCounts.get(tx.transaction_id) ?? 0) > 1,
      }));

      return jsonResponse({ transactions: result, has_more: pageRows.length === limit });
    }

    if (method === "GET" && path.match(/^plaid-transactions\/[^/]+\/splits$/)) {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const transactionId = path.split("/")[1];
       const { data: splits, error } = await supabase
         .from("transaction_assignments")
         .select("person_id, amount")
         .eq("transaction_id", transactionId)
         .eq("user_id", auth.userId)
         .not("amount", "is", null)
         .gt("amount", 0);
      if (error) throw new ApiError(502, error.message);
      return jsonResponse({
        splits: (splits ?? []).map((s: any) => ({
          person_id: s.person_id,
          amount: s.amount,
        })),
      });
    }

    if (method === "POST" && path.match(/^plaid-transactions\/[^/]+\/assignment$/)) {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const transactionId = path.split("/")[1];
      const body = await req.json().catch(() => ({}));
      await ensureDefaultPerson(auth.userId);
      const personId = body.person_id ? String(body.person_id) : null;

      if (personId) {
        const person = await getHouseholdPerson(auth.userId, personId);
        if (!person) throw new ApiError(404, "Household member not found");
      }

      const { data: txRows, error: txError } = await supabase
        .from("plaid_transactions")
        .select("transaction_id")
        .eq("transaction_id", transactionId)
        .eq("user_id", auth.userId)
        .eq("is_removed", false)
        .limit(1);
      if (txError) throw new ApiError(502, txError.message);
      if (!txRows || txRows.length === 0) throw new ApiError(404, "Transaction not found");

      if (!personId) {
        const primary = await ensureDefaultPerson(auth.userId);
        await supabase
          .from("transaction_assignments")
          .delete()
          .eq("transaction_id", transactionId)
          .eq("user_id", auth.userId);
        await calculateStatementSummaries(auth.userId);
        return jsonResponse({
          ok: true,
          transaction_id: transactionId,
          person_id: primary.person_id,
          assignment_source: "default",
        });
      }

       // Delete any existing assignment for this transaction
       const { error: deleteError } = await supabase
         .from("transaction_assignments")
         .delete()
         .eq("transaction_id", transactionId)
         .eq("user_id", auth.userId);
       if (deleteError) throw new ApiError(502, deleteError.message);

       const { data: rows, error } = await supabase
         .from("transaction_assignments")
         .insert({
           transaction_id: transactionId,
           user_id: auth.userId,
           person_id: personId,
           amount: null,
           assignment_source: "manual",
           event_id: null,
           updated_at: new Date().toISOString(),
         })
         .select();
      if (error) throw new ApiError(502, error.message);
      await calculateStatementSummaries(auth.userId);
      return jsonResponse({ ok: true, assignment: rows?.[0] });
    }

    // --- Transaction split assignment ---
    if (method === "POST" && path.match(/^plaid-transactions\/[^/]+\/assignment-split$/)) {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const transactionId = path.split("/")[1];
      const body = await req.json().catch(() => ({}));
      const splits = Array.isArray(body.splits) ? body.splits : [];

      if (splits.length === 0) {
        throw new ApiError(400, "At least one split is required");
      }

      // Validate splits
      let totalAmount = 0;
      for (const split of splits) {
        if (!split.person_id || typeof split.amount !== 'number' || split.amount <= 0) {
          throw new ApiError(400, "Each split must have person_id and positive amount");
        }
        const person = await getHouseholdPerson(auth.userId, split.person_id);
        if (!person) throw new ApiError(404, `Household member not found: ${split.person_id}`);
        totalAmount += split.amount;
      }

      const { data: txRows, error: txError } = await supabase
        .from("plaid_transactions")
        .select("transaction_id, amount")
        .eq("transaction_id", transactionId)
        .eq("user_id", auth.userId)
        .eq("is_removed", false)
        .limit(1);
      if (txError) throw new ApiError(502, txError.message);
      if (!txRows || txRows.length === 0) throw new ApiError(404, "Transaction not found");

      const txAmount = Math.abs(Number(txRows[0].amount));
      const splitTotal = Math.round(totalAmount * 100);
      const txTotal = Math.round(txAmount * 100);
      if (splitTotal !== txTotal) {
        throw new ApiError(400, `Split amounts must sum to transaction amount (${txAmount})`);
      }

      // Delete existing assignments for this transaction
      await supabase
        .from("transaction_assignments")
        .delete()
        .eq("transaction_id", transactionId)
        .eq("user_id", auth.userId);

      // Insert new split assignments
      const assignmentRows = splits.map((split) => ({
        transaction_id: transactionId,
        user_id: auth.userId,
        person_id: split.person_id,
        amount: split.amount,
        assignment_source: "manual",
        event_id: null,
        updated_at: new Date().toISOString(),
      }));

      const { error } = await supabase
        .from("transaction_assignments")
        .insert(assignmentRows);
      if (error) throw new ApiError(502, error.message);

      await calculateStatementSummaries(auth.userId);
      return jsonResponse({ ok: true, splits: assignmentRows });
    }

    // --- Household people DELETE ---
    if (method === "DELETE" && path.startsWith("household/people/")) {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const personId = path.split("/")[2];
      if (!personId) {
        throw new ApiError(400, "Invalid person ID");
      }
      const { data, error } = await supabase
        .from("household_people")
        .delete()
        .eq("person_id", personId)
        .eq("user_id", auth.userId)
        .select();
      if (error) throw new ApiError(502, error.message);
      if (!data || data.length === 0) throw new ApiError(404, "Household person not found");
      return jsonResponse({ ok: true, deleted: true, person_id: personId });
    }

    // --- Household members ---
    if (method === "GET" && path === "household/members") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const { data, error } = await supabase
        .from("household_members")
        .select("user_id, role, joined_at, invite_code")
        .eq("household_id", auth.userId);
      if (error) throw new ApiError(502, error.message);
      return jsonResponse({ members: data ?? [] });
    }

    if (method === "POST" && path === "household/members/join") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const body = await req.json().catch(() => ({}));
      const inviteCode = body.invite_code ? String(body.invite_code).toUpperCase().trim() : null;
      if (!inviteCode) {
        throw new ApiError(400, "invite_code is required");
      }

      // Find the household owner by invite code
      const { data: owner, error: ownerError } = await supabase
        .from("household_members")
        .select("household_id, user_id")
        .eq("invite_code", inviteCode)
        .eq("household_id", "user_id") // Only owners have household_id = user_id
        .limit(1);
      if (ownerError) throw new ApiError(502, ownerError.message);
      if (!owner || owner.length === 0) {
        throw new ApiError(404, "Invalid or expired invite code");
      }

      const householdId = owner[0].household_id;
      if (householdId === auth.userId) {
        throw new ApiError(400, "Cannot join your own household");
      }

      // Check if already a member
      const { data: existing } = await supabase
        .from("household_members")
        .select("user_id")
        .eq("household_id", householdId)
        .eq("user_id", auth.userId)
        .limit(1);
      if (existing && existing.length > 0) {
        throw new ApiError(409, "Already a member of this household");
      }

      const { data, error } = await supabase
        .from("household_members")
        .insert({ household_id: householdId, user_id: auth.userId, role: "member" })
        .select();
      if (error) {
        if (error.code === "23505") {
          throw new ApiError(409, "Already a member of this household");
        }
        throw new ApiError(502, error.message);
      }
      return jsonResponse({ member: data?.[0], household_id: householdId });
    }

    if (method === "POST" && path === "household/members") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const body = await req.json().catch(() => ({}));
      const userId = body.user_id ? String(body.user_id) : null;
      if (!userId) {
        throw new ApiError(400, "user_id is required");
      }
      if (userId === auth.userId) {
        throw new ApiError(400, "Cannot add yourself as a household member");
      }
      const { data, error } = await supabase
        .from("household_members")
        .insert({ household_id: auth.userId, user_id: userId, role: "member" })
        .select();
      if (error) {
        if (error.code === "23505") {
          throw new ApiError(409, "User is already a member of this household");
        }
        throw new ApiError(502, error.message);
      }
      return jsonResponse({ member: data?.[0] });
    }

    if (method === "DELETE" && path.startsWith("household/members/")) {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const targetUserId = path.split("/")[2];
      if (!targetUserId) {
        throw new ApiError(400, "Invalid member ID");
      }
      const { error } = await supabase
        .from("household_members")
        .delete()
        .eq("household_id", auth.userId)
        .eq("user_id", targetUserId);
      if (error) throw new ApiError(502, error.message);
      return jsonResponse({ ok: true, removed_user_id: targetUserId });
    }

    // --- Transaction household visibility ---
    if (method === "PATCH" && path.match(/^plaid-transactions\/[^/]+\/household-visible$/)) {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const transactionId = path.split("/")[1];
      const body = await req.json().catch(() => ({}));
      const visible = body.household_visible === true;

      const { data: txRows, error: txError } = await supabase
        .from("plaid_transactions")
        .select("transaction_id")
        .eq("transaction_id", transactionId)
        .eq("user_id", auth.userId)
        .eq("is_removed", false)
        .limit(1);
      if (txError) throw new ApiError(502, txError.message);
      if (!txRows || txRows.length === 0) throw new ApiError(404, "Transaction not found");

      await supabase
        .from("plaid_transactions")
        .update({ household_visible: visible })
        .eq("transaction_id", transactionId)
        .eq("user_id", auth.userId);

      return jsonResponse({ ok: true, transaction_id: transactionId, household_visible: visible });
    }

    // --- Card event household visibility ---
    if (method === "PATCH" && path.match(/^card-events\/[^/]+\/household-visible$/)) {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const eventId = path.split("/")[1];
      const body = await req.json().catch(() => ({}));
      const visible = body.household_visible === true;

      const { data: eventRows, error: eventError } = await supabase
        .from("card_events")
        .select("event_id")
        .eq("event_id", eventId)
        .eq("user_id", auth.userId)
        .limit(1);
      if (eventError) throw new ApiError(502, eventError.message);
      if (!eventRows || eventRows.length === 0) throw new ApiError(404, "Card event not found");

      await supabase
        .from("card_events")
        .update({ household_visible: visible })
        .eq("event_id", eventId)
        .eq("user_id", auth.userId);

      return jsonResponse({ ok: true, event_id: eventId, household_visible: visible });
    }

    // --- CSV Import ---
    if (method === "POST" && path === "csv-import/preview") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const body = await req.json().catch(() => ({}));
      const accountId = body.account_id ? String(body.account_id) : null;
      const csvText = body.csv_text ? String(body.csv_text) : null;

      if (!accountId || !csvText) {
        throw new ApiError(400, "account_id and csv_text are required");
      }

      const result = await generateCsvPreview(auth.userId, accountId, csvText);
      return jsonResponse(result);
    }

    if (method === "POST" && path === "csv-import/confirm") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const body = await req.json().catch(() => ({}));
      const accountId = body.account_id ? String(body.account_id) : null;
      const rows = Array.isArray(body.rows) ? body.rows : [];
      const filename = body.filename ? String(body.filename) : "import.csv";

      if (!accountId || rows.length === 0) {
        throw new ApiError(400, "account_id and rows are required");
      }

      const result = await confirmCsvImport(auth.userId, accountId, rows, filename);
      return jsonResponse(result);
    }

     if (method === "GET" && path === "csv-import/history") {
       const auth = await authenticateRequest(authorization);
       if (auth.userId === null) {
         throw new ApiError(403, "A user-linked device key or Supabase session is required");
       }
       const limit = Math.min(parseInt(url.searchParams.get("limit") || "50", 10), 100);
       const offset = parseInt(url.searchParams.get("offset") || "0", 10);

       const { data, error, count } = await supabase
         .from("csv_import_history")
         .select("*", { count: "exact" })
         .eq("user_id", auth.userId)
         .order("created_at", { ascending: false })
         .range(offset, offset + limit - 1);

       if (error) throw new ApiError(502, error.message);
       return jsonResponse({ imports: data ?? [], total: count ?? 0 });
     }

     // --- Manual card catalog sync ---
     if (method === "POST" && path === "card-catalog/sync-now") {
       // Require authentication for manual sync
       const auth = await authenticateRequest(authorization);
       if (auth.userId === null) {
         throw new ApiError(403, "A user-linked device key or Supabase session is required");
       }
       
       const result = await syncCardCatalog();
       return jsonResponse(result);
     }

     // --- Cron card catalog sync ---
     if ((method === "GET" || method === "POST") && path === "cron/card-catalog-sync") {
       const cronSecret = Deno.env.get("CRON_SECRET");
       if (!cronSecret) throw new ApiError(503, "Scheduled sync is not configured");

       let supplied: string | null = null;
       try {
         supplied = getBearerToken(authorization);
       } catch {
         throw new ApiError(401, "Unauthorized cron request");
       }
       if (supplied !== cronSecret) {
         throw new ApiError(401, "Unauthorized cron request");
       }

       const result = await syncCardCatalog();
       return jsonResponse(result);
     }

     // --- Create manual credit card ---
    if (method === "POST" && path === "plaid-credit-accounts/manual") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const body = await req.json().catch(() => ({}));
      const name = body.name?.trim();
      if (!name || name.length > 100) {
        throw new ApiError(400, "Invalid card name");
      }

      const { data, error } = await supabase
        .from("plaid_credit_accounts")
        .insert({
          user_id: auth.userId,
          account_id: `manual_${crypto.randomUUID()}`,
          name,
          official_name: name,
          mask: "0000",
          type: "credit",
          subtype: "credit_card",
          iso_currency_code: "USD",
          institution_name: "Manual Entry",
          item_id: null,
        })
        .select()
        .single();

      if (error) throw new ApiError(502, error.message);

      return jsonResponse({
        account_id: data.account_id,
        account_name: data.name,
      });
    }

    // --- Credit card display name ---
    if (method === "PATCH" && path.match(/^plaid-credit-accounts\/[^/]+\/display-name$/)) {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const accountId = path.split("/")[1];
      const body = await req.json().catch(() => ({}));
      const displayName = body.display_name?.trim() || null;

      const { data: check, error: checkError } = await supabase
        .from("plaid_credit_accounts")
        .select("account_id")
        .eq("account_id", accountId)
        .eq("user_id", auth.userId)
        .limit(1);
      if (checkError) throw new ApiError(502, checkError.message);
      if (!check || check.length === 0) throw new ApiError(404, "Credit card not found");

      const { data: updated, error: updateError } = await supabase
        .from("plaid_credit_accounts")
        .update({ display_name: displayName })
        .eq("account_id", accountId)
        .eq("user_id", auth.userId)
        .select();
      if (updateError) throw new ApiError(502, updateError.message);
      if (!updated || updated.length === 0) throw new ApiError(502, "Could not save the credit card name");

      return jsonResponse({
        account_id: accountId,
        display_name: displayName,
        account_name: creditCardDisplayName(updated[0]),
      });
    }

    // --- Cycle start ---
    if (method === "PUT" && path.match(/^plaid-credit-accounts\/[^/]+\/cycle-start$/)) {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const accountId = path.split("/")[1];
      const body = await req.json().catch(() => ({}));
      const cycleStartDate = body.cycle_start_date;

      const { data: accounts, error: acctError } = await supabase
        .from("plaid_credit_accounts")
        .select("account_id")
        .eq("account_id", accountId)
        .eq("user_id", auth.userId)
        .limit(1);
      if (acctError) throw new ApiError(502, acctError.message);
      if (!accounts || accounts.length === 0) throw new ApiError(404, "Credit card not found");

      const { data: statements, error: stmtError } = await supabase
        .from("plaid_liability_snapshots")
        .select("statement_issue_date")
        .eq("account_id", accountId)
        .eq("user_id", auth.userId)
        .order("statement_issue_date", { ascending: false })
        .limit(1);
      if (stmtError) throw new ApiError(502, stmtError.message);
      if (!statements || statements.length === 0) throw new ApiError(409, "Sync statement data before setting the prior statement date");

      const currentIssueDate = statements[0].statement_issue_date;
      const currentDate = new Date(currentIssueDate);
      const newDate = new Date(cycleStartDate);
      if (newDate >= currentDate) {
        throw new ApiError(422, "Prior statement date must be earlier than the current statement date");
      }

      await supabase
        .from("card_cycle_start_overrides")
        .upsert({
          user_id: auth.userId,
          account_id: accountId,
          statement_issue_date: currentIssueDate,
          cycle_start_date: cycleStartDate,
          updated_at: new Date().toISOString(),
        }, { onConflict: "user_id,account_id,statement_issue_date" });

      await calculateStatementSummaries(auth.userId);
      return jsonResponse({
        ok: true,
        account_id: accountId,
        statement_issue_date: currentIssueDate,
        cycle_start_date: cycleStartDate,
        cycle_start_source: "user_entered",
      });
    }

    // --- Wallet summary ---
    if (method === "GET" && path === "wallet/summary") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const userId = auth.userId;

      const items = await fetchUserRows("plaid_items", userId, { orderBy: "created_at.asc,item_id.asc" });
      const activeItemIds = new Set(
        (items ?? [])
          .filter((item) => (item.status ?? "connected") !== "disconnected")
          .map((item) => item.item_id),
      );

      const accounts = await fetchUserRows("plaid_credit_accounts", userId, { orderBy: "account_id.asc" });

      // Only credit accounts attached to an active (non-disconnected) item count as cards.
      // Rows with a null item_id (e.g. manually added accounts) are retained.
      const connectedAccounts = accounts.filter((account) => {
        const type = String(account.account_type ?? "credit");
        if (type !== "credit") return false;
        const itemId = account.item_id;
        return itemId == null || activeItemIds.has(itemId);
      });

      function dollarsToCents(value: unknown): number | null {
        if (value == null) return null;
        try {
          const d = new Decimal(String(value));
          if (!d.isFinite()) return null;
          return d.times(100).toDecimalPlaces(0, Decimal.ROUND_HALF_UP).toNumber();
        } catch {
          return null;
        }
      }

      const buckets = new Map<string, {
        currency: string;
        creditLimitCents: number;
        balanceCents: number;
        cardCount: number;
        accountsWithLimit: number;
        accountsWithBalance: number;
      }>();

      for (const account of connectedAccounts) {
        const currency = String(account.iso_currency_code ?? "UNKNOWN");
        let bucket = buckets.get(currency);
        if (!bucket) {
          bucket = {
            currency,
            creditLimitCents: 0,
            balanceCents: 0,
            cardCount: 0,
            accountsWithLimit: 0,
            accountsWithBalance: 0,
          };
          buckets.set(currency, bucket);
        }
        bucket.cardCount += 1;
        const limitCents = dollarsToCents(account.credit_limit);
        const balanceCents = dollarsToCents(account.current_balance);
        if (limitCents != null && limitCents > 0) {
          bucket.creditLimitCents += limitCents;
          bucket.accountsWithLimit += 1;
        }
        if (balanceCents != null) {
          bucket.balanceCents += balanceCents;
          bucket.accountsWithBalance += 1;
        }
      }

      const currencyList = Array.from(buckets.values()).sort((a, b) => {
        if (b.balanceCents !== a.balanceCents) return b.balanceCents - a.balanceCents;
        if (b.cardCount !== a.cardCount) return b.cardCount - a.cardCount;
        return a.currency.localeCompare(b.currency);
      });
      const primaryCurrency = currencyList[0]?.currency ?? null;

      // Highest payment in the past 30 days: largest absolute negative amount.
      // Prefer explicitly-coded payment transactions; fall back to any negative,
      // non-pending, non-removed transaction. Within the chosen pool, prefer the
      // primary currency, then the largest payment overall (reported in its own
      // currency so it is never mislabeled).
      let highestPayment: {
        transaction_id: string;
        account_id: string | null;
        account_name: string;
        amount_cents: number;
        currency: string;
        date: string | null;
        name: string | null;
        merchant_name: string | null;
      } | null = null;

      const activeAccountIds = connectedAccounts
        .map((account) => account.account_id)
        .filter((id): id is string => typeof id === "string" && id.length > 0);

      if (activeAccountIds.length > 0) {
        const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
        let paymentRows: any[] = [];

        const poolQuery = (transactionCode: string | null) => {
          let query = supabase
            .from("plaid_transactions")
            .select(
              "transaction_id,account_id,amount,iso_currency_code,date,name,merchant_name,transaction_code",
            )
            .eq("user_id", userId)
            .eq("is_removed", false)
            .eq("pending", false)
            .lt("amount", 0)
            .gte("date", since)
            .in("account_id", activeAccountIds)
            .order("amount", { ascending: true })
            .limit(500);
          if (transactionCode) {
            query = query.eq("transaction_code", transactionCode);
          }
          return query;
        };

        const { data: codedPayments, error: codedError } = await poolQuery("payment");
        if (codedError) throw new ApiError(502, codedError.message);
        paymentRows = codedPayments ?? [];
        if (paymentRows.length === 0) {
          const { data: allPayments, error: allError } = await poolQuery(null);
          if (allError) throw new ApiError(502, allError.message);
          paymentRows = allPayments ?? [];
        }

        if (paymentRows.length > 0) {
          const byAccount = new Map(connectedAccounts.map((a) => [a.account_id, a]));
          let chosen = paymentRows[0];
          if (primaryCurrency != null) {
            const primaryRow = paymentRows.find(
              (row) => String(row.iso_currency_code ?? "UNKNOWN") === primaryCurrency,
            );
            if (primaryRow) chosen = primaryRow;
          }
          const amountCents = dollarsToCents(chosen.amount);
          const account = byAccount.get(chosen.account_id ?? undefined);
          highestPayment = {
            transaction_id: String(chosen.transaction_id ?? ""),
            account_id: chosen.account_id ?? null,
            account_name: creditCardDisplayName(account ?? {}),
            amount_cents: amountCents != null ? Math.abs(amountCents) : 0,
            currency: String(chosen.iso_currency_code ?? "UNKNOWN"),
            date: chosen.date ?? null,
            name: chosen.name ?? null,
            merchant_name: chosen.merchant_name ?? null,
          };
        }
      }

      return jsonResponse({
        card_count: connectedAccounts.length,
        primary_currency: primaryCurrency,
        currencies: currencyList.map((bucket) => ({
          currency: bucket.currency,
          credit_limit_cents: bucket.creditLimitCents,
          balance_cents: bucket.balanceCents,
          card_count: bucket.cardCount,
          accounts_with_limit: bucket.accountsWithLimit,
          accounts_with_balance: bucket.accountsWithBalance,
        })),
        highest_payment: highestPayment,
      });
    }

    // --- Statement cycles ---
    if (method === "GET" && path === "owed/statement-cycles") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      await ensureDefaultPerson(auth.userId);

      const summaries = await fetchUserRows("card_statement_summaries", auth.userId, { orderBy: "statement_issue_date.desc,account_id.asc" });
      const accounts = await fetchUserRows("plaid_credit_accounts", auth.userId, { orderBy: "account_id.asc" });
      const people = await fetchUserRows("household_people", auth.userId, { orderBy: "created_at.asc,person_id.asc" });

      const { data: liabilityStates, error: liabError } = await supabase
        .from("plaid_liability_sync_state")
        .select("status,reason,account_count,statement_count,updated_at")
        .eq("user_id", auth.userId)
        .limit(1);
      if (liabError) throw new ApiError(502, liabError.message);

      const accountNames = new Map(accounts.map((row) => [row.account_id, creditCardDisplayName(row)]));
      const latestByAccount = new Map<string, Record<string, unknown>>();
      for (const summary of summaries) {
        if (!latestByAccount.has(summary.account_id as string)) {
          latestByAccount.set(summary.account_id as string, summary);
        }
      }

      const readyRows = Array.from(latestByAccount.values()).filter(
        (row) => ["READY", "REVIEW"].includes(row.status as string) && row.amount_owed !== null
      );

      const liabilityState = liabilityStates?.[0] ?? null;
      const accountCurrency = new Map(accounts.map((row) => [row.account_id, row.iso_currency_code ?? "UNKNOWN"]));
      const totalsByCurrency: Record<string, Decimal> = {};
      for (const row of readyRows) {
        const currency = accountCurrency.get(row.account_id as string) ?? "UNKNOWN";
        const amount = new Decimal(String(row.amount_owed));
        totalsByCurrency[currency] = (totalsByCurrency[currency] ?? new Decimal(0)).plus(amount);
      }

      let total: string | null = null;
      if (Object.keys(totalsByCurrency).length === 1) {
        total = Object.values(totalsByCurrency)[0]!.toFixed(2);
      }

      const liabilityDataCurrent =
        liabilityState &&
        liabilityState.status === "synced" &&
        (liabilityState.statement_count as number) > 0;

      const allAccountsReady =
        latestByAccount.size > 0 &&
        latestByAccount.size === accounts.length &&
        readyRows.length === latestByAccount.size &&
        liabilityDataCurrent;

      if (!allAccountsReady || Object.keys(totalsByCurrency).length !== 1) {
        total = null;
      }

      let totalStatus: string;
      if (anyReadyRow(row => row.status === "REVIEW", readyRows)) {
        totalStatus = "REVIEW";
      } else if (!allAccountsReady) {
        totalStatus = "WAITING_FOR_STATEMENTS";
      } else if (Object.keys(totalsByCurrency).length > 1) {
        totalStatus = "MULTI_CURRENCY";
      } else if (readyRows.length > 0) {
        totalStatus = "READY";
      } else {
        totalStatus = "WAITING_FOR_STATEMENTS";
      }

      return jsonResponse({
        primary_person: people.find((p) => p.is_default) ?? null,
        accounts: summaries.map((row) => ({
          ...row,
          account_name: accountNames.get(row.account_id as string) ?? "Card",
          currency: accountCurrency.get(row.account_id as string) ?? "UNKNOWN",
        })),
        credit_accounts: accounts.map((row) => ({
          ...row,
          account_name: creditCardDisplayName(row),
          plaid_name: row.name,
        })),
        current_total_owed: total,
        totals_by_currency: Object.fromEntries(
          Object.entries(totalsByCurrency).map(([k, v]) => [k, (v as Decimal).toFixed(2)])
        ),
        liabilities: liabilityState,
        total_status: totalStatus,
      });
    }

    // --- Card event reconciliations sync ---
    if (method === "POST" && path === "card-event-reconciliations/sync") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const body = await req.json();
      const reconciliations: any[] = Array.isArray(body) ? body : [];

      for (const rec of reconciliations) {
        const { data: eventExists, error: eventErr } = await supabase
          .from("card_events")
          .select("event_id")
          .eq("event_id", rec.event_id)
          .eq("user_id", auth.userId)
          .limit(1);
        if (eventErr) throw new ApiError(502, eventErr.message);
        if (!eventExists || eventExists.length === 0) {
          throw new ApiError(403, "A reconciliation references an event not owned by this user");
        }

        if (rec.candidate_transaction_id) {
          const { data: txExists, error: txErr } = await supabase
            .from("plaid_transactions")
            .select("transaction_id")
            .eq("transaction_id", rec.candidate_transaction_id)
            .eq("user_id", auth.userId)
            .limit(1);
          if (txErr) throw new ApiError(502, txErr.message);
          if (!txExists || txExists.length === 0) {
            throw new ApiError(403, "A reconciliation references a transaction not owned by this user");
          }
        }
      }

      const rows = reconciliations.map((rec) => ({
        ...rec,
        user_id: auth.userId,
        updated_at: new Date().toISOString(),
      }));

      if (rows.length > 0) {
        const { error } = await supabase
          .from("card_event_reconciliations")
          .upsert(rows, { onConflict: "event_id" });
        if (error) throw new ApiError(502, error.message);
      }

      return jsonResponse({ ok: true, saved: rows.length, user_id: auth.userId });
    }

    // --- List reconciliations ---
    if (method === "GET" && path === "card-event-reconciliations") {
      const auth = await authenticateRequest(authorization);
      if (auth.userId === null) {
        throw new ApiError(403, "A user-linked device key or Supabase session is required");
      }
      const limit = Math.min(parseInt(url.searchParams.get("limit") || "500", 10), 500);
      const offset = parseInt(url.searchParams.get("offset") || "0", 10);

      const { data, error } = await supabase
        .from("card_event_reconciliations")
        .select("*")
        .eq("user_id", auth.userId)
        .order("updated_at", { ascending: false })
        .order("event_id", { ascending: true })
        .range(offset, offset + limit - 1);
      if (error) throw new ApiError(502, error.message);
      return jsonResponse({ reconciliations: data ?? [] });
    }

    // --- Login page (static) ---
    if (method === "GET" && path === "login") {
      return new Response(null, {
        status: 302,
        headers: { Location: "/login.html" },
      });
    }

    return jsonResponse({ detail: "Not found" }, 404);
  } catch (error) {
    return errorResponse(error);
  }
});

function anyReadyRow(predicate: (row: Record<string, unknown>) => boolean, rows: Record<string, unknown>[]): boolean {
  return rows.some(predicate);
}
