"""Split-routing hook (Step 5) — widen discovery for large orders.

Full multi-pool split execution requires deep baseline changes; this module
triggers extra pool discovery above ``SPLIT_THRESHOLD_WEI`` so large trades
see more liquidity venues before route resolution.
"""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger(__name__)

# Default: 1 WETH (18 decimals). Override via env MINER_SPLIT_THRESHOLD_WEI.
import os

SPLIT_THRESHOLD_WEI = int(os.environ.get("MINER_SPLIT_THRESHOLD_WEI", str(10**18)))


def maybe_widen_for_size(
    solver: Any,
    chain_id: int,
    pool_states: dict[str, dict[str, Any]],
    token_in: str,
    token_out: str,
    amount_in: int,
) -> dict[str, dict[str, Any]]:
    """Pre-generate_plan hook for large input amounts."""
    if amount_in < SPLIT_THRESHOLD_WEI:
        return pool_states

    from strategies.dex_aggregator import extra_dex_top, routing_top

    logger.info(
        "split_routing_top: input %d >= threshold %d — widening pools",
        amount_in,
        SPLIT_THRESHOLD_WEI,
    )
    pool_states = routing_top.pre_large_order_discovery(
        solver, chain_id, pool_states, token_in, token_out, amount_in, SPLIT_THRESHOLD_WEI,
    )
    return extra_dex_top.ensure_extra_dex_pairs(
        solver, chain_id, pool_states, token_in, token_out,
    )
