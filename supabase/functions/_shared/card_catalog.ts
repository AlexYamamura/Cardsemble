import { supabase } from "./supabase.ts";

/**
 * Fetches card data from the external API and updates the local card_catalog table.
 * 
 * @returns Object with sync results
 */
export async function syncCardCatalog(): Promise<{ ok: true; updated: number; inserted: number }> {
  try {
    // Fetch data from external API
    const response = await fetch("https://opencard-db.davidweng.workers.dev/v1/cards?country=us");
    
    if (!response.ok) {
      throw new Error(`Failed to fetch card data: ${response.status} ${response.statusText}`);
    }
    
    const cards: any[] = await response.json();
    
    if (!Array.isArray(cards)) {
      throw new Error("Expected array of cards from API");
    }
    
    let inserted = 0;
    let updated = 0;
    
    // Process each card
    for (const card of cards) {
      if (!card.id) {
        continue; // Skip cards without ID
      }
      
      // Upsert the card into the card_catalog table
      const { error } = await supabase
        .from("card_catalog")
        .upsert(
          { 
            id: card.id,
            data: card,
            updated_at: new Date().toISOString()
          },
          { onConflict: "id" }
        );
      
      if (error) {
        throw error;
      }
      
      // Note: Supabase doesn't distinguish between insert and update in the response
      // for upsert, so we'll count all as updated for simplicity
      // In a more complex implementation, we could check if the record existed first
      updated++;
    }
    
    return { ok: true, updated, inserted: 0 };
  } catch (error) {
    console.error("Error syncing card catalog:", error);
    throw error;
  }
}