# Architecture

Backend stays unmodified. Android translates dsh wire traffic into neutral UI models.

```text
dsh web
  | HTTP:  /api/session.list, /api/session.prompt, /api/respond, ...
  | WS:    /api/events.mux, /api/events.host
  v
:core:network               transport only
  v
:core:harness-adapter       dsh anti-corruption layer, translation state machine
  v
:core:domain                Session, ChatMessage, TimelineItem
  v
:app                        Compose screens, spatial layout, theming
```

## Layout ownership

All layout decisions are made in `:app`. The harness adapter never tells the UI where a
component should be placed. It only publishes facts:

- a message was committed
- a tool call started/finished
- an approval was requested
- session running state changed

Changing portrait/landscape/tablet/foldable layouts is exclusively an `:app` change.
