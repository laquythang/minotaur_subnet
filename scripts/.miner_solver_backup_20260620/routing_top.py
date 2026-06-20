"""Extended pool discovery (Step 3) — extra pools / intermediaries on Base.

Hooks into MinerSolver without modifying baseline_solver.py.
"""

from __future__ import annotations

import logging
import time
from typing import Any

logger = logging.getLogger(__name__)

# Extra Uniswap V3 pools on Base (liquidity anchors beyond baseline seed list).
EXTRA_KNOWN_POOLS: dict[int, list[str]] = {
    8453: [
        "0x6dEB966667399DC25638737757926b8FAd57E9D6",  # WETH/USDC 0.3%
        "0x4e962BB7552d341E4D76d4C8Ae9a75a891EeE80B",  # WETH/USDC (alt tier)
        "0xA9e6fa10aEe579384B3E5972E762405A8a7382d8",  # WETH/USDbC legacy
    ],
}

# Extra multi-hop intermediaries per chain (addresses from SDK token registry).
EXTRA_INTERMEDIARIES: dict[int, list[str]] = {
    8453: [
        "0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb",  # DAI
        "0xd9aAEc86B65C86f64A6523d06323C7744897E90",  # USDC (native)
    ],
}


def refresh_discovery_cache(solver: Any) -> None:
    """Invalidate pair / pool caches so the next route attempt re-discovers."""
    for chain_id in list(getattr(solver, "_pool_cache", {}).keys()):
        solver._pool_cache.pop(chain_id, None)
        solver._pool_cache_time.pop(chain_id, None)
    stale = list(getattr(solver, "_pair_discovery_cache", {}).keys())
    for key in stale:
        solver._pair_discovery_cache.pop(key, None)
    logger.info("routing_top: discovery caches cleared (%d pair markers)", len(stale))


def merge_extra_pools(
    chain_id: int,
    pool_states: dict[str, dict[str, Any]],
    solver: Any,
) -> dict[str, dict[str, Any]]:
    """Query EXTRA_KNOWN_POOLS via RPC and merge into pool_states."""
    extras = EXTRA_KNOWN_POOLS.get(chain_id, [])
    if not extras:
        return pool_states

    w3 = solver._get_web3(chain_id)
    if w3 is None:
        return pool_states

    merged = dict(pool_states)
    added = 0
    for addr in extras:
        key = addr.lower()
        if key in {k.lower() for k in merged}:
            continue
        state = solver._query_pool_state(w3, addr)
        if state is not None:
            merged[addr] = state
            added += 1

    if added:
        logger.debug("routing_top: merged %d extra known pools on chain %d", added, chain_id)
        solver._pool_cache[chain_id] = merged
        solver._pool_cache_time[chain_id] = time.time()
    return merged


def ensure_extended_route(
    solver: Any,
    chain_id: int,
    pool_states: dict[str, dict[str, Any]],
    token_in: str,
    token_out: str,
) -> dict[str, dict[str, Any]]:
    """After baseline discovery, probe extra intermediary pairs."""
    if not solver._rpc_urls.get(chain_id):
        return pool_states

    extras = EXTRA_INTERMEDIARIES.get(chain_id, [])
    if not extras:
        return pool_states

    in_l, out_l = token_in.lower(), token_out.lower()
    for mid in extras:
        mid_l = mid.lower()
        if mid_l in (in_l, out_l):
            continue
        solver._discover_pools_for_pair(chain_id, token_in, mid, pool_states)
        solver._discover_pools_for_pair(chain_id, mid, token_out, pool_states)

    return pool_states


def pre_large_order_discovery(
    solver: Any,
    chain_id: int,
    pool_states: dict[str, dict[str, Any]],
    token_in: str,
    token_out: str,
    amount_in: int,
    split_threshold: int,
) -> dict[str, dict[str, Any]]:
    """Step 5 hook: widen discovery for large orders."""
    if amount_in < split_threshold:
        return pool_states
    logger.debug(
        "routing_top: large order (%d wei) — extra discovery pass", amount_in,
    )
    refresh_discovery_cache(solver)
    return ensure_extended_route(solver, chain_id, pool_states, token_in, token_out)
