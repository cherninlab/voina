# Match flow

Optional and host-authoritative (`gameplay/match/match_flow.gd`). Enable **Match · first to 3 round wins** before **Host game**, launch with `-- --host --match`, or run `python3 scripts/playtest.py host --match`. Joining players need no flag. Without it, play stays free-for-all with instant respawn.

- **Waiting** until at least two players are in.
- **Countdown** 3 s: everyone respawns at full health on their spawn point; combat is frozen (no attacks, bolts, dashes, guard raising or damage). Pending swings and dash immunity are cancelled. Movement stays free for now.
- **Round** 90 s: the player who lands the kill wins the round. Killer credit requires an actual fighter's combat controller; an NPC sharing the host's authority does not count as the host. An unattributed or NPC death gives the round to the only opponent; with multiple opponents it is a draw. On timeout, sudden death starts.
- **Sudden death** 15 s: a red ring closes from the arena corners (17 m) to the centre (1.5 m). Outside it you lose 20 health per second (5 every 0.25 s), ignoring block, parry and dash; a ring death counts like an unattributed death. If the ring closes fully, the healthiest player wins; equal health is a draw. The host applies the damage; every peer draws the ring from the replicated match clock (`gameplay/match/sudden_death_ring.gd`).
- **Round over** 3 s, then the next countdown. **First to three** wins the match; combat stays frozen on the result, and a rematch with fresh scores starts after 10 s.
- A leaving opponent returns the match to waiting.

The host runs the clock from physics delta (never `Engine.time_scale`) and replicates state, time, scores and the banner to every peer, including late joiners. The banner sits at the top centre of the screen.

Tested by `res://tests/match_test.tscn` (full match on the host) and a two-process smoke pair (a client sees the replicated round). Not yet: locked movement during countdown, kit selection.
