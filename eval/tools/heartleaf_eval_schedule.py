"""Deterministic pair-covering schedules; never submit or count planned games as played.

Every game has nine distinct policies. Policies are opaque identities: variants
of the same soul are deliberately allowed to meet. For 81 policies meeting once, an affine plane achieves the minimum 90 games.
Other sizes use greedy coverage without a minimum-game or seat-balance guarantee.
"""

from collections import Counter
from itertools import combinations


def _keys(policy_keys: list[str]) -> list[str]:
    if (
        len(policy_keys) < 9
        or any(not isinstance(key, str) or not key for key in policy_keys)
        or len(set(policy_keys)) != len(policy_keys)
    ):
        raise ValueError("cohort requires at least nine distinct nonempty policy keys")
    return sorted(policy_keys)


def count_pairs(policy_keys: list[str], rosters: list[list[str]]) -> dict:
    """Count a supplied roster list, including zero counts for unplayed pairs."""
    keys = _keys(policy_keys)
    known = set(keys)
    counts = dict.fromkeys(combinations(keys, 2), 0)
    for roster in rosters:
        if len(roster) != 9 or len(set(roster)) != 9 or not set(roster) <= known:
            raise ValueError("each game must contain nine distinct known policies")
        for pair in combinations(sorted(roster), 2):
            counts[pair] += 1
    return counts


def affine_schedule(keys: list[str]) -> list[list[str]]:
    """Lines of AG(2,9): 81 points, 90 nine-point lines, each pair on one line.

    Represent GF(9) as a+b*t over GF(3), with t*t=-1 (t*t+1 is
    irreducible over GF(3)). Arithmetic modulo 9 would not be a field.
    Consecutive groups of nine are vertical lines, preserving the first
    nine rosters of the earlier greedy schedule, including their seat rotation.
    """

    def add(x: int, y: int) -> int:
        return (x % 3 + y % 3) % 3 + 3 * ((x // 3 + y // 3) % 3)

    def multiply(x: int, y: int) -> int:
        a, b = x % 3, x // 3
        c, d = y % 3, y // 3
        return (a * c - b * d) % 3 + 3 * ((a * d + b * c) % 3)

    rosters = [keys[start : start + 9] for start in range(0, 81, 9)]
    for slope in range(9):
        for intercept in range(9):
            rosters.append(
                [keys[9 * x + add(multiply(slope, x), intercept)] for x in range(9)]
            )
    return [roster[i % 9 :] + roster[: i % 9] for i, roster in enumerate(rosters)]


def covering_schedule(policy_keys: list[str], meetings: int = 2) -> list[list[str]]:
    """Fill nine-seat games until every unordered pair meets at least M times.

    Start with the most underserved policy and one of its missing partners.
    Add policies that cover the most remaining pair meetings, breaking ties by
    participation and stable identity. Each game strictly reduces the deficit.
    Rotate the seat order between games without claiming full seat balancing.
    """
    keys = _keys(policy_keys)
    if type(meetings) is not int or meetings < 1:
        raise ValueError("meetings must be a positive integer")
    if len(keys) == 81 and meetings == 1:
        return affine_schedule(keys)
    remaining = {
        key: {other: meetings for other in keys if other != key} for key in keys
    }
    appearances = Counter()
    games = []
    while any(any(row.values()) for row in remaining.values()):
        degrees = {key: sum(row.values()) for key, row in remaining.items()}
        first = min(keys, key=lambda key: (-degrees[key], appearances[key], key))
        partners = [key for key in keys if key != first and remaining[first][key] > 0]
        second = min(partners, key=lambda key: (-degrees[key], appearances[key], key))
        roster = [first, second]
        while len(roster) < 9:
            candidates = [key for key in keys if key not in roster]
            next_key = min(
                candidates,
                key=lambda key: (
                    -sum(remaining[key][member] > 0 for member in roster),
                    -degrees[key],
                    appearances[key],
                    key,
                ),
            )
            roster.append(next_key)
        for left, right in combinations(roster, 2):
            if remaining[left][right] > 0:
                remaining[left][right] -= 1
                remaining[right][left] -= 1
        appearances.update(roster)
        offset = len(games) % 9
        games.append(roster[offset:] + roster[:offset])
    return games


def completed_pair_coverage(policy_keys: list[str], episodes: list[dict]) -> dict:
    """Count reconciled, accepted seven-day episodes once each, excluding canaries.

    `acceptance_verified` is an explicit import from the hosted verifier, not
    inferred from a successful request or a planned roster. This pure function
    does not independently authenticate external evidence.
    """
    seen = {}
    rosters = []
    for episode in episodes:
        identity = episode.get("episode_id")
        if not isinstance(identity, str) or not identity:
            raise ValueError("episode evidence requires a nonempty episode_id")
        signature = (
            episode.get("status"),
            episode.get("max_days"),
            episode.get("acceptance_verified"),
            tuple(episode.get("policy_keys", [])),
        )
        if identity in seen:
            if seen[identity] != signature:
                raise ValueError(f"conflicting evidence for episode {identity}")
            continue
        seen[identity] = signature
        if (
            episode.get("status") == "completed"
            and episode.get("max_days") == 7
            and episode.get("acceptance_verified") is True
        ):
            rosters.append(episode.get("policy_keys", []))
    return count_pairs(policy_keys, rosters)
