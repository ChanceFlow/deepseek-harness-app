# :core:harness-adapter

Anti-corruption layer. This is the only module allowed to know dsh endpoint names, event names,
wire schemas, and translation rules.

Input : dsh wire traffic (HTTP + WebSocket)
Output: neutral `:core:domain` models only.
