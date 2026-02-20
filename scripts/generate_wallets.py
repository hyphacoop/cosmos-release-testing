# Python script to generate defined wallets and store it in cosmos_wallets.json
# Usage: python generate_wallets.py <number of wallets to generate>
#        python generate_wallets.py 100

import sys
from cosmospy import generate_wallet

if len(sys.argv) > 1:
    count = int(sys.argv[1])
else:
    count=1

def generate_bulk_wallets():
    wallets = []
    
    for i in range(1, count+1):
        # Generates a random mnemonic and derives the first address (index 0)
        wallet = generate_wallet()
        
        wallets.append({
            "index": i,
            "address": wallet["address"],
            # "mnemonic": wallet["mnemonic"]
        })
    
    return wallets

# Generate the wallets
new_wallets = generate_bulk_wallets()

# Print the first 5 results as a preview
# print(f"{'No.':<5} | {'Cosmos Address':<50}")
# print("-" * 60)
# for w in new_wallets[:5]:
#     print(f"{w['index']:<5} | {w['address']:<50}")

# print(f"\n... generated {len(new_wallets)} wallets in total.")

# Optional: Save to a file
import json
with open("cosmos_wallets.json", "w") as f:
    json.dump(new_wallets, f, indent=4)

