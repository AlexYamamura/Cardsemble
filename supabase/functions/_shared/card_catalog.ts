import { supabase } from "./supabase.ts";

interface CardCatalogApiResponse {
  total: number;
  limit: number;
  offset: number;
  data: any[];
}

/**
 * Fetches card data from the external API and updates the local card_catalog table.
 *
 * The external API returns a paginated envelope:
 *   {"total":N,"limit":N,"offset":N,"data":[...]}
 * where `data` is the actual list of cards. This function fetches all pages,
 * checks which records already exist in `card_catalog` to accurately classify
 * each as an insert or an update, then batch-upserts all records.
 *
 * @returns Object with sync results: total cards processed, inserts, updates
 */
export async function syncCardCatalog(): Promise<{
  ok: true;
  updated: number;
  inserted: number;
  total: number;
}> {
  try {
    const baseUrl = "https://opencard-db.davidweng.workers.dev/v1/cards";

    // First request to discover pagination info and get the first page
    const response = await fetch(`${baseUrl}?country=us`);

    if (!response.ok) {
      throw new Error(`Failed to fetch card data: ${response.status} ${response.statusText}`);
    }

    const responseBody: CardCatalogApiResponse = await response.json();

    // The `data` field holds the actual array of cards
    const cards: any[] = Array.isArray(responseBody.data) ? responseBody.data : [];

    // Collect remaining pages if the API is paginated
    const total = responseBody.total ?? 0;
    const limit = responseBody.limit ?? cards.length;
    const offset = responseBody.offset ?? 0;

    if (total > offset + cards.length) {
      let currentOffset = offset + cards.length;
      while (currentOffset < total) {
        const pageResponse = await fetch(
          `${baseUrl}?country=us&offset=${currentOffset}&limit=${limit}`,
        );

        if (!pageResponse.ok) {
          throw new Error(
            `Failed to fetch card data page at offset ${currentOffset}: ${pageResponse.status} ${pageResponse.statusText}`,
          );
        }

        const pageBody: CardCatalogApiResponse = await pageResponse.json();
        const pageData = Array.isArray(pageBody.data) ? pageBody.data : [];
        cards.push(...pageData);
        currentOffset += pageData.length;

        // Guard against the API not honoring offset/returning empty
        if (pageData.length === 0) break;
      }
    }

    // Pre-fetch existing record IDs so we can classify inserts vs updates
    const existingIds = new Set<string>();
    const batchSize = 1000; // Respect Supabase IN clause limits
    for (let i = 0; i < cards.length; i += batchSize) {
      const batch = cards.slice(i, i + batchSize);
      const ids = batch.map((c) => c.id).filter((id): id is string => Boolean(id));
      if (ids.length === 0) continue;

      const { data: existing, error: fetchError } = await supabase
        .from("card_catalog")
        .select("id")
        .in("id", ids);

      if (fetchError) {
        throw fetchError;
      }

      if (existing) {
        for (const row of existing) {
          if (row.id) existingIds.add(row.id);
        }
      }
    }

    // Build upsert records and classify
    let inserted = 0;
    let updated = 0;
    const now = new Date().toISOString();
    const upsertBatch: { id: string; data: any; updated_at: string }[] = [];

    for (const card of cards) {
      if (!card.id) {
        continue; // Skip cards without ID
      }

      if (existingIds.has(card.id)) {
        updated++;
      } else {
        inserted++;
      }

      upsertBatch.push({
        id: card.id,
        data: card,
        updated_at: now,
      });
    }

    // Batch upsert all records in one call
    if (upsertBatch.length > 0) {
      const { error: upsertError } = await supabase
        .from("card_catalog")
        .upsert(upsertBatch, { onConflict: "id" });

      if (upsertError) {
        throw upsertError;
      }
    }

    return { ok: true, updated, inserted, total: cards.length };
  } catch (error) {
    console.error("Error syncing card catalog:", error);
    throw error;
  }
}