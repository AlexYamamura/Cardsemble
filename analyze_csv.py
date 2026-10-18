#!/usr/bin/env python3
"""Chase CSV vs Local DB Duplicate Detection Analysis"""
import sqlite3
import re
from collections import Counter

# Read CSV from the pasted content
csv_text = """Transaction Date,Post Date,Description,Category,Type,Amount,Memo
10/08/2026,10/11/2026,TST*WUSONG ROAD - CAMBRI,Food & Drink,Sale,-91.08,
10/08/2026,10/11/2026,LUNETTE OPTIC CAMBRIDGE,Health & Wellness,Sale,-10.00,
10/11/2026,10/11/2026,GOOGLE *Play,Shopping,Sale,-25.00,
10/02/2026,10/04/2026,DD *DOORDASH DOMINOS,Food & Drink,Sale,-106.13,
09/29/2026,09/30/2026,Payment Thank You-Mobile,,Payment,6119.99,
09/28/2026,09/29/2026,THE LAKEHOUSE,Entertainment,Sale,-6000.00,
09/26/2026,09/27/2026,MBTA-550047114842,Travel,Sale,-2.40,
09/25/2026,09/25/2026,AUTOMATIC PAYMENT - THANK,,Payment,1535.80,
09/20/2026,09/21/2026,DUNKIN #357337,Food & Drink,Sale,-10.69,
09/12/2026,09/13/2026,MBTA-550047114842,Travel,Sale,-2.40,
09/08/2026,09/09/2026,MBTA-550047114842,Travel,Sale,-2.40,
08/31/2026,09/02/2026,TST*DOLANS UYGHUR CUISI,Food & Drink,Sale,-102.10,
08/31/2026,09/01/2026,CVS/PHARMACY #09562,Health & Wellness,Sale,-34.46,
08/30/2026,08/31/2026,SQ *DVINE MEDITERRANEAN E,Food & Drink,Sale,-16.62,
08/30/2026,08/31/2026,SQ *CONFETTI ITALIAN ICE,Groceries,Sale,-7.00,
08/28/2026,08/30/2026,CVS/PHARMACY #09550,Health & Wellness,Sale,-16.08,
08/29/2026,08/30/2026,DAISY CHAIN FIELDS,Entertainment,Sale,-5.39,
08/29/2026,08/30/2026,UBER   *TRIP,Travel,Sale,-16.05,
08/29/2026,08/30/2026,TST* BUSHFIRE KITCHEN - T,Food & Drink,Sale,-22.78,
08/26/2026,08/26/2026,AUTOMATIC PAYMENT - THANK,,Payment,1744.89,
08/24/2026,08/26/2026,RAISING CANES 0570,Food & Drink,Sale,-33.15,
08/23/2026,08/24/2026,CLIPPER TRANSIT FARE,Travel,Sale,-2.85,
08/22/2026,08/24/2026,CLIPPER TRANSIT FARE,Travel,Sale,-2.85,
08/22/2026,08/24/2026,CLIPPER TRANSIT FARE,Travel,Sale,-2.85,
08/22/2026,08/23/2026,COSTCO GAS #0453,Gas,Sale,-51.89,
08/21/2026,08/23/2026,CLIPPER TRANSIT FARE,Travel,Sale,-2.85,
08/21/2026,08/23/2026,CLIPPER TRANSIT FARE,Travel,Sale,-11.80,
08/22/2026,08/23/2026,TST* MAMA GO'S FILIPINO C,Food & Drink,Sale,-47.62,
08/21/2026,08/23/2026,SQ *PURPLE KOW,Food & Drink,Sale,-26.85,
08/19/2026,08/20/2026,TST* BATIFOL - CAMBRIDGE,Food & Drink,Sale,-130.00,
08/18/2026,08/19/2026,CVS/PHARMACY #01215,Health & Wellness,Sale,-25.78,
08/18/2026,08/19/2026,CVS/PHARMACY #01215,Health & Wellness,Sale,-25.03"""

# Parse CSV
lines = csv_text.strip().split('\n')
header = lines[0].split(',')
rows = []
for line in lines[1:]:
    if not line.strip():
        continue
    parts = line.split(',')
    # Handle descriptions with commas
    row = {
        'transaction_date': parts[0].strip() if len(parts) > 0 else '',
        'post_date': parts[1].strip() if len(parts) > 1 else '',
        'description': parts[2].strip() if len(parts) > 2 else '',
        'category': parts[3].strip() if len(parts) > 3 else '',
        'type': parts[4].strip() if len(parts) > 4 else '',
        'amount': float(parts[5].strip()) if len(parts) > 5 else 0.0,
        'memo': parts[6].strip() if len(parts) > 6 else '',
    }
    if row['type'].lower() in ['sale', 'payment', 'credit', 'return']:
        rows.append(row)

print(f"Parsed {len(rows)} CSV rows")

# Load DB transactions
conn = sqlite3.connect("transactions.db")
conn.row_factory = sqlite3.Row
db_txns = [dict(r) for r in conn.execute("SELECT * FROM transactions").fetchall()]
print(f"Loaded {len(db_txns)} DB transactions\n")

# normalizeDate
def normalize_date(d):
    if not d:
        return ""
    parts = re.split(r'[-/]', d)
    if len(parts) != 3:
        return d
    if len(parts[0]) == 4:  # YYYY-MM-DD
        return f"{parts[0]}-{parts[1].zfill(2)}-{parts[2].zfill(2)}"
    # MM/DD/YYYY
    return f"{parts[2]}-{parts[0].zfill(2)}-{parts[1].zfill(2)}"

# normalizeMerchant (simplified)
def normalize_merchant(name):
    if not name:
        return ""
    n = name.lower()
    n = re.sub(r'^(sq|dd|tst)\s*\*?\s*', '', n)
    n = re.sub(r'\s+', ' ', n)
    return n.strip()

# Find MBTA transactions in DB
print("=== MBTA TRANSACTIONS IN DB ===")
for t in db_txns:
    m = normalize_merchant(t.get('name') or t.get('merchant_name') or '')
    if 'mbta' in m:
        print(f"  {t['date']} | {t['amount']:>8.2f} | {t.get('name', t.get('merchant_name', ''))}")

print("\n=== CLIPPER TRANSIT FARES IN DB ===")
for t in db_txns:
    m = normalize_merchant(t.get('name') or t.get('merchant_name') or '')
    if 'clipper' in m or 'transit fare' in m.lower():
        print(f"  {t['date']} | {t['amount']:>8.2f} | {t.get('name', t.get('merchant_name', ''))}")

# Count duplicates in CSV
print("\n=== INTRA-CSV DUPLICATES ===")
from collections import defaultdict
csv_sigs = defaultdict(list)
for i, row in enumerate(rows):
    sig = (normalize_date(row['post_date']), abs(row['amount']), normalize_merchant(row['description']))
    csv_sigs[sig].append(i)

dup_count = 0
for sig, indices in csv_sigs.items():
    if len(indices) > 1:
        dup_count += len(indices)
        dates = [rows[i]['post_date'] for i in indices]
        amounts = [rows[i]['amount'] for i in indices]
        descs = [rows[i]['description'][:30] for i in indices]
        print(f"  {sig[0]} | ${sig[1]/100:.2f} | '{sig[2][:30]}'")
        print(f"    CSV rows: {list(indices)} - same date/amount/merchant")

print(f"\nTotal intra-CSV duplicate rows: {dup_count}")

# Check date mismatches
print("\n=== DATE MISMATCH ANALYSIS ===")
targets = [
    ('10/02/2026', '10/04/2026', 'DD *DOORDASH DOMINOS', -106.13),
    ('07/16/2026', '07/17/2026', 'COSTCO WHSE', -226.73),
]

# Check if DB has transactions close to these dates
print("Checking if DB has costco on 2026-07-16:")
for t in db_txns:
    if 'costco' in (t.get('name', '') + (t.get('merchant_name') or '')).lower():
        print(f"  DB: {t['date']} | {t['amount']:>8.2f} | {t.get('name', t.get('merchant_name', ''))}")