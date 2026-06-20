"""Cross-DEX factory discovery (Step 4) — PancakeSwap V3 on Base.

Uses the same pool state shape as Uniswap V3; pools are tagged ``dex='uniswap_v3'``
so the existing Uni router builder can execute them when routed via factory lookup.
"""

from __future__ import annotations

import logging
import time
from typing import Any

logger = logging.getLogger(__name__)

_ZERO = "0x" + "0" * 40

# Alternate V3-compatible factories (name, address) per chain.
EXTRA_V3_FACTORIES: dict[int, list[tuple[str, str]]] = {
    8453: [
        ("pancakeswap_v3", "0x0BFbCF9fa4f463C559dD9461F4557717CA573b74"),
    ],
}

_FEE_TIERS = (100, 500, 2500, 3000, 10000)


def discover_extra_v3_factories(
    solver: Any,
    chain_id: int,
    token_a: str,
    token_b: str,
    pool_states: dict[str, dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    """Probe extra V3 factories for pools between token_a and token_b."""
    factories = EXTRA_V3_FACTORIES.get(chain_id, [])
    if not factories or not solver._rpc_urls.get(chain_id):
        return pool_states

    w3 = solver._get_web3(chain_id)
    if w3 is None:
        return pool_states

    a_l, b_l = token_a.lower(), token_b.lower()
    pair_key = (chain_id, "extra_v3", min(a_l, b_l), max(a_l, b_l))
    cache = getattr(solver, "_pair_discovery_cache", {})
    ttl = getattr(solver, "_pool_cache_ttl", 12.0)
    if time.time() - cache.get(pair_key, 0) < ttl:
        return pool_states

    from strategies.dex_aggregator.baseline_solver import _FACTORY_ABI

    discovered = 0
    for name, factory_addr in factories:
        try:
            factory = w3.eth.contract(
                address=w3.to_checksum_address(factory_addr),
                abi=_FACTORY_ABI,
            )
        except Exception as exc:
            logger.debug("extra_dex_top: factory %s init failed: %s", name, exc)
            continue

        for fee in _FEE_TIERS:
            try:
                pool_addr = factory.functions.getPool(
                    w3.to_checksum_address(token_a),
                    w3.to_checksum_address(token_b),
                    fee,
                ).call()
            except Exception:
                continue
            if not pool_addr or pool_addr == _ZERO:
                continue
            if pool_addr.lower() in {k.lower() for k in pool_states}:
                continue
            state = solver._query_pool_state(w3, pool_addr)
            if state is not None:
                meta = dict(state)
                meta.setdefault("dex", "uniswap_v3")
                meta["factory"] = name
                pool_states[pool_addr] = meta
                discovered += 1

    cache[pair_key] = time.time()
    if discovered:
        logger.debug(
            "extra_dex_top: +%d pools from extra factories (%s / %s)",
            discovered, token_a[:10], token_b[:10],
        )
    return pool_states


def ensure_extra_dex_pairs(
    solver: Any,
    chain_id: int,
    pool_states: dict[str, dict[str, Any]],
    token_in: str,
    token_out: str,
) -> dict[str, dict[str, Any]]:
    """Direct pair + intermediary pairs via extra factories."""
    discover_extra_v3_factories(solver, chain_id, token_in, token_out, pool_states)

    from strategies.dex_aggregator import routing_top

    for mid in routing_top.EXTRA_INTERMEDIARIES.get(chain_id, []):
        if mid.lower() in (token_in.lower(), token_out.lower()):
            continue
        discover_extra_v3_factories(solver, chain_id, token_in, mid, pool_states)
        discover_extra_v3_factories(solver, chain_id, mid, token_out, pool_states)

    return pool_states
