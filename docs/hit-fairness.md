# Hit fairness

Answer to [llm-question-hit-fairness.md](llm-question-hit-fairness.md), implemented in `gameplay/player/hit_resolver.gd`.

## Diagnosis (before)

Remote bodies chase 30 Hz snapshots with an exponential lerp at rate 20, so a viewer shows another player about `VIEW_LAG` = 1/20 s + half an interval ≈ 67 ms behind the snapshots it has received. A client attacker A at time `a` sees target B as the host received it at `a − ow(A) − VIEW_LAG`, where `ow` is one-way latency. Its request lands at `a + ow(A)`. The old code judged B where the host displayed it then, at `a + ow(A) − VIEW_LAG`. The mismatch is one full round trip:

| RTT | Mismatch | Target walking 6.5 m/s | Target dashing 16 m/s |
| --- | --- | --- | --- |
| 20 ms | 20 ms | 0.13 m | 0.32 m |
| 60 ms | 60 ms | 0.39 m | 0.96 m |
| 100 ms | 100 ms | 0.65 m | 1.6 m |

The host's own player had zero mismatch: it sees and is judged against the same displayed bodies. That is the listen-server advantage.

Melee was worse. The host started a client's windup `ow(A)` late. It also measured the cone from the host's smoothed copy of the attacker, about `ow(A)` + 67 ms behind, which mostly cancelled the owner's 7 m/s lunge (≈0.7 m of a 2.2 m reach at 60 ms RTT). Line-of-sight hits on the 0.4 m capsule are dominated by latency; the snapshot interval and lerp only add a constant that the host already shared.

## Decision

Server-side rewind with a rewind time measured by the server.

- **History:** every physics tick the host records each player's latest `sync_position` (what it received, not its smoothed display) in a 0.4 s ring buffer. Teleports and respawns clear it.
- **Rewind:** `RTT(attacker) + VIEW_LAG`, capped at **200 ms**. RTT is ENet's own measurement, so clients send no timestamps and there is nothing to forge. A client can only inflate its RTT, which the cap bounds; RTT up to ~133 ms is fully compensated. The host's own player rewinds `VIEW_LAG`, which keeps it consistent with what the host screen showed.
- **Attacker** is taken from its latest replicated position, not the smoothed copy, so the lunge counts.
- **Beam:** analytic segment-vs-capsule test (radius 0.4, axis ±0.5 m) against rewound centers. Walls come from a physics ray that excludes every player body, so rewound targets cannot be blocked by present bodies, and cover still protects.
- **Melee:** the same 70° / 2.2 m cone and chest line-of-sight, against rewound centers, every active tick, one hit per target.
- **Swing timing:** the host back-dates a client's melee windup by `RTT/2`, capped at **60 ms** (`head_start`), so the host's active window lines up with what the attacker saw.
- **Defense stays in the present.** Block, parry (plus the existing defender latency grace), dash ranged immunity and facing are the defender's state on the host now. Rewind decides *whether the swing reached you*; your latest inputs decide *what it did*.

## Rejected alternatives

- **Client hit claims** (`target_id`, `hit_point`) with tolerance: easy for hitscan, but it doesn't map to melee cones or future projectiles, and it lets clients pick targets. Rewind covers all three with one history.
- **Client-sent view timestamps:** these need clock sync and are forgeable. Server-measured RTT gives the same answer within jitter.
- **Buffered snapshot interpolation:** it gives a precise view delay, but it adds latency to every remote body. The current lerp's lag is modelled as `VIEW_LAG`. Revisit if Tailscale jitter makes hits feel inconsistent.
- **Delaying the host's own inputs:** it makes the host feel worse to make clients feel better. Players who want strict fairness can use dedicated mode (`--server`).

## Known trade-offs

- **Shot behind cover:** a target that reached cover on its own screen can still be hit for up to the attacker's rewind (≤ 200 ms, ≤ 1.3 m of walking). That's accepted shooter favour, bounded by the cap.
- **Residual error:** snapshot timing jitter (±17 ms at 30 Hz) and RTT jitter remain. No WAN or Tailscale measurements have been made; manual two-Mac play must judge feel.
- **Future projectiles** should use this history only for the first sweep from the shooter's view time, then simulate in the present.

## Verification

`tests/hit_resolver_test.gd` covers history pruning and interpolation, rewind and head-start caps, the capsule ray, the cone, cover, excluded bodies, and the shortened host windup. The two-process smoke test still lands beam and melee hits through the new path. Neither test injects artificial latency; on loopback the RTT is near zero.
