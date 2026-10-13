# Corridor 12 — GDD

# Corridor 12 — GDD (Notion)

**Version:** v0.1

**Engine:** Godot 4 + GDScript

**Platforms:** PC → Mobile/Tablet

**MVP Timebox:** 2 weeks

## High Concept

Simulation/strategy about planning humanitarian aid convoys under time, safety, and logistics constraints. Optimize **impact, equity, and safety** across a dynamic road network.

## Design Pillars

- **Equity-first distribution**: success requires fair geographic & group coverage.
- **Transparent risk**: readable risk/constraint surfaces; no arbitrary surprises.
- **Short decisions, long impact**: today’s plan shapes tomorrow’s capacity.
- **Simple UI, real depth**: approachable controls with meaningful trade-offs.

## Core Loop

1. **Plan**: set priorities (commodities/areas/convoys), build routes.
2. **Simulate Day**: run the day timeline; fuel/ETA windows; random events.
3. **Deliver & Resolve**: arrivals, holds, reroutes; checkpoint windows.
4. **Assess & Upgrade**: KPIs, equity balance; unlock small improvements.

## Systems

### Map Graph

- **Nodes**: districts / checkpoints / warehouses / distribution points.
- **Edges**: travel time, risk, fuel cost, capacity, time windows.
- **Layers**: risk heatmap, accessibility, congestion.

### Resources

Fuel, drivers (fatigue), vehicle capacity, cold-chain (for meds/fresh food).

### Demand & Equity

- Per-node **Demand** accumulating **Backlog** each day.
- **Equity Index** tracking variance of coverage across areas.

### Events

Small cards modifying windows/risk/fuel/weather for 1–2 days with probabilities.

## KPIs

| KPI | Description |
| --- | --- |
| People Reached | Delivered beneficiaries per day |
| On-Time % | Share of deliveries within windows |
| Incident Count | Security/operational disruptions |
| Equity Variance | Variance of coverage across areas |
| Cold-Chain Breach % | % of cold cargo breaching constraints |
| Fuel/ton-km | Fuel efficiency normalized by ton-km |

## Progression

- Unlocks: better comms, nearer storage, driver training, fleet upgrades.
- Difficulty adds: closed roads → time windows → cold-chain → multi-commodity.

## UX

- **Center**: map with drag-and-drop routing & risk colors.
- **Left**: demand/priorities/resources.
- **Right**: active convoys & schedules.
- **Bottom**: day timeline; play/pause/speed.
- Tooltips, color scales, Undo/Redo.

## Data Examples (JSON)

### Map

```json
{  "nodes": [    {"id":"W1","type":"warehouse","capacity":1000},    {"id":"D1","type":"district","demand":{"food":200,"med":50,"shelter":80}},    {"id":"X1","type":"checkpoint","window":{"start":8,"end":12}}  ],  "edges": [    {"from":"W1","to":"X1","time":20,"risk":0.1,"fuel":5,"capacity":4},    {"from":"X1","to":"D1","time":25,"risk":0.3,"fuel":6,"capacity":2}  ]}
```

### Events

```json
[  {"id":"evt_window_cut","title":"Checkpoint window reduced","effect":{"checkpoint":"X1","end":10},"duration_days":1,"prob":0.2},  {"id":"evt_fuel_shortage","title":"Fuel shortage","effect":{"fuel_multiplier":1.2},"duration_days":2,"prob":0.15}]
```

## Godot Structure (High-level)

```
Main
 ├─ MapRoot (Node2D)
 │   ├─ GraphManager (Node)
 │   ├─ RouteDrawer (Node2D)
 ├─ ConvoyManager (Node)
 ├─ EventManager (Node)
 ├─ SimulationClock (Node)
 ├─ KPITracker (Node)
 ├─ UI (Panels + Timeline)
 └─ Audio
```

## Routing (Multi-criteria)

`cost(edge) = α*time + β*risk + γ*fuel + δ*equity_penalty`

A* over graph; weights configurable; heuristic = time estimate to goal.

## Simulation Tick

- Tick = 1 minute. Update positions, fuel, windows, events, KPIs.
- End-of-day: deliveries applied; backlog updated; KPIs recorded.

## MVP Definition of Done

- Run 3 consecutive days without crashes.
- Complete 3 short scenarios with comparable KPIs.
- In-game tooltips for core concepts.

---

# Databases

corridor12_backlog
