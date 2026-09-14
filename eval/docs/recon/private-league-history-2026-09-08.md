# Private league history and current constraint

Investigated 2026-09-08, live reads at approximately 18:34 UTC. Source: freshly fetched Metta `origin/main`, commit `29a6b65a28677b1f69140d9da8724fce9f0ad536`, inspected with `git show` in the separate `metta_5` checkout. No production writes or backend edits.

## Conclusion

**Private leagues were not removed.** Their flags, access checks, and team-only visibility API still exist. The earlier statement should be narrowed: there is no supported API/CLI path to create a **new, persistently private, enabled Coworld league** under the current seed system. Private-league support and private-league creation are different questions.

James's recollection is consistent with the history. Two changes explain the present limitation:

1. **2026-05-20 UTC:** [PR 13720](https://app.graphite.dev/github/pr/Metta-AI/metta/13720), commit `ddb82475de04d774d5ee2588ad5fafbdc15e7043`, removed internal `POST /v2/leagues`. That endpoint accepted `public` and `hidden`, created a nonseeded league, and was team-only. Creation helpers moved to test support.
2. **2026-08-01 UTC (July 31 Pacific):** [PR 18757](https://app.graphite.dev/github/pr/Metta-AI/metta/18757), commit `cb17a91a93805cd24572e78a82e1e3d21df44d2a`, made seed reconciliation restore `public` and `hidden` unconditionally. Previously those corrections ran only when the seed itself requested `hidden=true`. Consequently, making an ordinary seeded league private through its visibility endpoint used to persist; now reconciliation restores the template. The PR explicitly treated private drift and disappearing public leagues as bugs.

This was not removal of all privacy functionality: [PR 20883](https://app.graphite.dev/github/pr/Metta-AI/metta/20883), commit `6567322eca`, added access for granted owners of private leagues on **2026-09-02 UTC**.

## Current source evidence

All paths below are relative to Metta at the pinned commit above.

| Surface | Current behavior | Source |
| --- | --- | --- |
| Existing league visibility | Team-only `POST /v2/leagues/{league_id}/visibility` writes both flags. | `app_backend/src/metta/app_backend/v2/routes/leagues.py:1914` |
| New Coworld league | CLI creates a league seed; no generic league-create route or UI remains. | `packages/coworld/src/coworld/cli.py:276`; `packages/coworld/src/coworld/upload.py:680` |
| Seed template | Sets `public=True`; `hidden` defaults to `False`. | `app_backend/src/metta/app_backend/v2/seed.py:393`, `:75` |
| Accepted overrides | `CoworldSeedOverrides` rejects extra keys and has no `public` or `hidden` override. | `app_backend/src/metta/app_backend/v2/seed.py:129` |
| Reconciliation | Restores both flags to template values. | `app_backend/src/metta/app_backend/v2/seed.py:660` |
| Seed deletion | DELETE disables the seed and immediately reconciles; it does not detach or delete the row. | `app_backend/src/metta/app_backend/v2/routes/coworld_league_seeds.py:995` |
| Disabled seed | Disables its league. Disabled leagues cannot be XP targets. | `app_backend/src/metta/app_backend/v2/seed.py:720`; `app_backend/src/metta/app_backend/v2/routes/experience_requests.py:204` |

The other production-tree `League(...)` constructors are seed reconciliation and a **local campaign bootstrap**. A test-support constructor also exists. None is an alternative supported hosted creation API; using them against production would require direct database writes, outside this task.

## Browse is not a privacy test

The catalog route excludes disabled leagues and non-Coworld games, then applies the shared visibility scope (`routes/leagues.py:390`). Anonymous readers get `public=true AND hidden=false`. Granted owners may also see private, nonhidden leagues; elevated team readers may see private leagues. Hidden leagues are excluded even for ordinary elevated team reads (`v2/permissions.py:134-177`). Platform-commissioner scope has a separate bypass, not an operator workaround for this task.

Browse consumes that catalog, applies search/category filters, and groups multiple leagues for one game into tabs rather than separate cards (`web/softmax.com/src/app/watch/Browse.tsx:906-946`). A league not appearing as a separate Browse card therefore does not establish privacy. `hidden` is also not a general unlisted-but-readable mode: shared child/detail visibility and XP targeting enforce that boundary.

## Live read-only verification

Used existing authenticated team access to `/observatory/sql/query`, executing SELECT only:

```sql
SELECT public, hidden, (disabled_at IS NULL) AS active, count(*)
FROM leagues
GROUP BY public, hidden, (disabled_at IS NULL)
ORDER BY public, hidden, active;
```

| public | hidden | active | count |
| --- | --- | --- | --- |
| false | false | false | 1 |
| true | false | false | 19 |
| true | false | true | 137 |

The one private league was `Vanilla Wow`, `league_d7bf3aea-fa8d-4661-9f60-ba9fbbde5fe5`, disabled since `2026-07-18T00:57:56.461803Z`, with its seed disabled. No currently active private or hidden league appeared in this database snapshot.

Both anonymous and elevated authenticated `GET /v2/leagues` returned HTTP 200 and **136 leagues**. The raw database count and catalog count have different scope; the catalog additionally requires a Coworld-backed game. This comparison establishes the same visible catalog count for those callers, not that private-league support has disappeared.

## Milestone decision

Proceed with the user-approved fallback: a separate `heartleaf-eval` Coworld and league-less private XP requests. Do not create a public league and race reconciliation, repurpose someone else's league, disable a seed to evade management, or use database writes. Preserve the distinction between request privacy, world visibility, and league visibility in results and verification.

### Fallback authorization and no-seed behavior

Source verification at the same pinned commit:

- Ordinary XP visibility requires persisted `request_spec.private == false`; setting `private=true` denies the public branch even without a league. The special public tournament-wave branch is not applicable to this milestone (`v2/permissions.py:259-278`).
- The requester retains access. A verified Softmax team **User** with elevated privileges receives the elevated resource scope and can read private requests (`authorization.py:88-99`, `:214-236`; `v2/permissions.py:315-365`). Player tokens do not gain elevation merely because their owner is on the team. Use normal user authentication with the existing elevated-privileges header, not new permission grants.
- Episode children derive game-level artifact visibility from their parent XP. Per-policy artifact manifests first require episode access, then narrow access to the relevant policy owner/team. Participation alone does not grant access (`v2/episode_artifacts.py:110-153`, `:388-414`, `:453-478`). An ordinary unrelated user therefore does not gain access from owning an original source soul or from the world being visible. This is source-backed behavior; hosted authorization readbacks remain a separate verification step.
- Uploading a Coworld does not itself create a league seed. The only production `CoworldLeagueSeed(...)` constructor is the explicit seed-create route (`v2/routes/coworld_league_seeds.py:480`). Reconciliation loads enabled seed rows and returns an empty cohort when none exist (`v2/seed.py:437-448`). **No seed is an intentional valid configuration**, not a missing setup step.

Keep returned signed artifact URLs private: authorization controls issuance, but a signed URL is itself temporary bearer access. Do not put URLs or downloaded souls into public results.
