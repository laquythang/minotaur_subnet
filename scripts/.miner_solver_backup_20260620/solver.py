"""Reference solver for Subnet 112 (Minotaur).

This is the file miners fork to ship their own strategy. The validator
harness imports ``SOLVER_CLASS`` from this module and calls
``generate_plan(intent, state, snapshot)`` on every order.

Default behaviour comes from ``BaselineSwapSolver`` in
``strategies/dex_aggregator/baseline_solver.py``, which on Base routes across both
Uniswap V3 and Aerodrome Slipstream pools, picks the best output
across DEXes, and falls back to multi-hop through common intermediary
tokens (WETH, USDC) when no direct pool wins.

Miner extensions (logic_miner_top.md steps 2–5):
  - zero_score_guard_top  — never raise from quote / generate_plan
  - routing_top           — extra Base pools + intermediaries
  - extra_dex_top         — PancakeSwap V3 factory on Base
  - split_routing_top     — widen discovery for large orders

The validator's screening pipeline builds this repo as a Docker image
``FROM ghcr.io/subnet112/solver-base:v1`` and runs the runner harness,
which loads ``SOLVER_CLASS`` from ``/app/solver/solver.py``.
"""

from __future__ import annotations

import logging
import os
from typing import Any

from strategies.dex_aggregator.baseline_solver import BaselineSwapSolver
from strategies.dex_aggregator import (
    extra_dex_top,
    routing_top,
    split_routing_top,
    zero_score_guard_top,
)
from minotaur_subnet.sdk.intent_solver import (
    MarketSnapshot,
    SolverMetadata,
)
from minotaur_subnet.shared.types import (
    AppIntentDefinition,
    ExecutionPlan,
    IntentState,
    QuoteResult,
)

logger = logging.getLogger(__name__)


SOLVER_NAME = os.environ.get("MINOTAUR_SOLVER_NAME", "my-solver")
SOLVER_VERSION = os.environ.get("MINOTAUR_SOLVER_VERSION", "0.1.0")
SOLVER_AUTHOR = os.environ.get("MINOTAUR_SOLVER_AUTHOR", "miner")


class MinerSolver(BaselineSwapSolver):
    """Top miner solver — baseline routing + local extensions (steps 2–5)."""

    def metadata(self) -> SolverMetadata:
        base = super().metadata()
        return SolverMetadata(
            name=SOLVER_NAME,
            version=SOLVER_VERSION,
            author=SOLVER_AUTHOR,
            description=(
                f"{base.description or 'Dex aggregator'} "
                "[miner: guard+routing+extra_dex+split]"
            ),
            supported_chains=base.supported_chains,
            supported_intent_types=base.supported_intent_types,
        )

    def _discover_pools(self, chain_id: int) -> dict[str, dict[str, Any]]:
        pools = super()._discover_pools(chain_id)
        return routing_top.merge_extra_pools(chain_id, pools, self)

    def _ensure_pools_for_route(
        self,
        chain_id: int,
        pool_states: dict[str, dict[str, Any]],
        token_in: str,
        token_out: str,
    ) -> dict[str, dict[str, Any]]:
        pool_states = super()._ensure_pools_for_route(
            chain_id, pool_states, token_in, token_out,
        )
        pool_states = routing_top.ensure_extended_route(
            self, chain_id, pool_states, token_in, token_out,
        )
        return extra_dex_top.ensure_extra_dex_pairs(
            self, chain_id, pool_states, token_in, token_out,
        )

    def generate_plan(
        self,
        intent: AppIntentDefinition,
        state: IntentState,
        snapshot: MarketSnapshot | None = None,
    ) -> ExecutionPlan:
        chain_id = state.chain_id or (snapshot.chain_id if snapshot else 1)
        try:
            swap_params = self._normalized_swap_params(intent, state)
            amount_in = int(swap_params.get("input_amount") or 0)
            token_in = swap_params.get("input_token", "")
            token_out = swap_params.get("output_token", "")
            if token_in and token_out and amount_in > 0 and self._rpc_urls.get(chain_id):
                pool_states = self._get_pool_states(chain_id, snapshot)
                if pool_states is not None:
                    if snapshot is not None and snapshot.pool_states and pool_states is snapshot.pool_states:
                        pool_states = dict(pool_states)
                    split_routing_top.maybe_widen_for_size(
                        self, chain_id, pool_states, token_in, token_out, amount_in,
                    )
        except Exception as exc:
            logger.debug("MinerSolver pre-discovery skipped: %s", exc)

        return zero_score_guard_top.guard_generate_plan(
            self, intent, state, snapshot,
        )

    def quote(
        self,
        intent: AppIntentDefinition,
        state: IntentState,
        snapshot: MarketSnapshot | None = None,
    ) -> QuoteResult:
        return zero_score_guard_top.guard_quote(self, intent, state, snapshot)


SOLVER_CLASS = MinerSolver
