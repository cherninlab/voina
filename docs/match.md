# Match flow

Optional and host-authoritative (`gameplay/match/match_flow.gd`). Enable **Match · first to 3 round wins** before **Host game**, launch with `-- --host --match`, or run `python3 scripts/playtest.py host --match`. Joining players need no flag. Without it, play stays free-for-all with instant respawn.

- **Waiting** until at least two players are in.
- **Countdown** 3 s: everyone respawns at full health on their spawn point; combat is frozen (no attacks, bolts, dashes or damage). Movement stays free for now.
- **Round** 90 s: the player who lands the kill wins the round. An unattributed death gives it to the only opponent. On timeout the healthiest player wins; equal health is a draw.
- **Round over** 3 s, then the next countdown. **First to three** wins the match; combat stays frozen on the result, and a rematch with fresh scores starts after 10 s.
- A leaving opponent returns the match to waiting.

The host runs the clock from physics delta (never `Engine.time_scale`) and replicates state, time, scores and the banner to every peer, including late joiners. The banner sits at the top centre of the screen.

Tested by `res://tests/match_test.tscn` (full match on the host) and a two-process smoke pair (a client sees the replicated round). Not yet: sudden-death ring, locked movement during countdown, kit selection.
