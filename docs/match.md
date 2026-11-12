# Match flow

Optional and host-authoritative (`gameplay/match/match_flow.gd`). Enable **Match · first to 3 round wins** before **Host game**, launch with `-- --host --match`, or run `python3 scripts/playtest.py host --match`. Joining players need no flag. Without it, play stays free-for-all with instant respawn.

- **Waiting** until at least two players are in.
- **Countdown** 3 s: everyone respawns at full health on their spawn point; combat is frozen (no attacks, bolts, dashes, guard raising or damage). Pending swings and dash immunity are cancelled. Movement, jumping, dashing and sword pull are locked while camera look stays free; the host snaps a player who drifts more than 0.75 m from its spawn point back (after a round-trip grace for in-flight snapshots).
- **Round** 90 s: the player who lands the kill wins the round. Killer credit requires an actual fighter's combat controller; an NPC sharing the host's authority does not count as the host. An unattributed or NPC death gives the round to the only opponent; with multiple opponents it is a draw. On timeout, sudden death starts.
- **Sudden death** 36 s: a red ring closes from the arena corners (40 m) to the centre (1.5 m) at about 1 m/s. Outside it you lose 20 health per second (5 every 0.25 s), ignoring block, parry and dash. Each pulse damages everyone before resolving the result: one death follows the unattributed-death rule above; multiple deaths in the same pulse are a draw, including both duelists dying. Child order does not select a winner. If the ring closes fully, the healthiest player wins; equal health is a draw. The host applies the damage; every peer draws the ring from the replicated match clock (`gameplay/match/sudden_death_ring.gd`).
- **Round over** 3 s, then the next countdown. **First to three** wins the match; combat stays frozen on the result, and a rematch with fresh scores starts after 10 s.
- A leaving opponent returns the match to waiting.

The host runs the clock from physics delta (never `Engine.time_scale`) and replicates state, time, scores and the banner to every peer, including late joiners. The banner sits at the top centre of the screen.

A replacement joining while a departed avatar awaits deletion waits for that avatar to exit the tree and release `MultiplayerSpawner` capacity. It inherits the match rules when it actually spawns. Leaving or stopping cancels pending arrivals; a failed spawn does not report success. Village starts are `(0, 0.95, ±3)` and `(7.5, 0.95, ±3)`, clear of static cover for the player capsule. The initial host/guest separation stays 6 m.

Tested by `res://tests/match_test.tscn` (full match and both child orders for lethal/nonlethal ring pulses), `res://tests/spawn_slot_test.tscn` (actual spawner replacement callbacks, pending leave/stop, village capsule clearance and settled spawns/respawns), and a two-process smoke pair (a client sees the replicated round). Not yet: kit selection.
