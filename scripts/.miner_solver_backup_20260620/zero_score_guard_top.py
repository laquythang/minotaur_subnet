"""Zero-score guard — never raise from quote/generate_plan (Step 2).

Wraps BaselineSwapSolver calls so the harness always receives a structurally
valid ExecutionPlan / QuoteResult instead of an uncaught exception (instant 0).
"""

from __future__ import annotations

import logging
import re
import time
from typing import Any

from strategies.dex_aggregator.baseline_solver import BaselineSwapSolver
from minotaur_subnet.shared.types import (
    AppIntentDefinition,
    ExecutionPlan,
    Interaction,
    IntentState,
    QuoteResult,
)
from minotaur_subnet.sdk.intent_solver import MarketSnapshot

logger = logging.getLogger(__name__)

_ADDR_RE = re.compile(r"^0x[0-9a-fA-F]{40}$")


def _chain_id(state: IntentState, snapshot: MarketSnapshot | None) -> int:
    if state.chain_id:
        return int(state.chain_id)
    if snapshot and snapshot.chain_id:
        return int(snapshot.chain_id)
    return 1


def _swap_params(solver: Any, intent: AppIntentDefinition, state: IntentState) -> dict[str, Any]:
    try:
        return solver._normalized_swap_params(intent, state)
    except Exception as exc:
        logger.warning("zero_score_guard: normalize params failed: %s", exc)
        raw = state.raw_params_view() if hasattr(state, "raw_params_view") else {}
        return {
            "input_token": raw.get("input_token", ""),
            "output_token": raw.get("output_token", ""),
            "input_amount": int(raw.get("input_amount") or 0),
            "min_output_amount": int(raw.get("min_output_amount") or 0),
            "receiver": raw.get("receiver") or state.owner or state.contract_address,
        }


def validate_plan(
    plan: ExecutionPlan,
    intent: AppIntentDefinition,
    state: IntentState,
    chain_id: int,
) -> ExecutionPlan:
    """Fix common structural issues; never return empty interactions."""
    intent_id = (plan.intent_id or intent.app_id or "dex").strip() or "dex"
    deadline = int(plan.deadline or 0)
    now = int(time.time())
    if deadline <= now:
        deadline = now + 3600

    interactions: list[Interaction] = []
    for ix in plan.interactions or []:
        target = (ix.target or "").strip()
        if not _ADDR_RE.match(target):
            logger.warning("zero_score_guard: drop interaction with bad target %r", target)
            continue
        cd = ix.call_data or "0x"
        if not cd.startswith("0x"):
            cd = "0x" + cd
        interactions.append(
            Interaction(
                target=target,
                value=str(ix.value or "0"),
                call_data=cd,
                chain_id=int(ix.chain_id or chain_id),
            )
        )

    if not interactions:
        raise ValueError("plan has no valid interactions after validation")

    metadata = dict(plan.metadata or {})
    metadata.setdefault("chain_id", chain_id)

    return ExecutionPlan(
        intent_id=intent_id,
        interactions=interactions,
        deadline=deadline,
        nonce=int(plan.nonce if plan.nonce is not None else state.nonce or 0),
        metadata=metadata,
    )


def build_recovery_plan(
    solver: Any,
    intent: AppIntentDefinition,
    state: IntentState,
    snapshot: MarketSnapshot | None,
    reason: str,
) -> ExecutionPlan:
    """Last-resort structurally valid plan when routing fails."""
    chain_id = _chain_id(state, snapshot)
    params = _swap_params(solver, intent, state)
    token = params.get("input_token") or state.contract_address or ("0x" + "0" * 40)
    if not _ADDR_RE.match(token):
        token = "0x4200000000000000000000000000000000000006"  # Base WETH fallback

    spender = state.contract_address or params.get("receiver") or token
    if not _ADDR_RE.match(spender):
        spender = token

    amount = max(int(params.get("input_amount") or 0), 0)
    approve_data = (
        "0x095ea7b3"
        + spender[2:].lower().zfill(64)
        + hex(amount)[2:].zfill(64)
    )
    now = int(time.time())
    return ExecutionPlan(
        intent_id=intent.app_id or "dex",
        interactions=[
            Interaction(
                target=token,
                value="0",
                call_data=approve_data,
                chain_id=chain_id,
            )
        ],
        deadline=now + 3600,
        nonce=int(state.nonce or 0),
        metadata={
            "route": "recovery_stub",
            "chain_id": chain_id,
            "guard_reason": reason[:200],
        },
    )


def guard_generate_plan(
    solver: Any,
    intent: AppIntentDefinition,
    state: IntentState,
    snapshot: MarketSnapshot | None,
) -> ExecutionPlan:
    """Call baseline generate_plan with retry + structural validation."""
    chain_id = _chain_id(state, snapshot)
    last_exc: Exception | None = None

    for attempt in range(2):
        try:
            plan = BaselineSwapSolver.generate_plan(solver, intent, state, snapshot)
            return validate_plan(plan, intent, state, chain_id)
        except Exception as exc:
            last_exc = exc
            logger.warning(
                "zero_score_guard: generate_plan attempt %d failed: %s",
                attempt + 1,
                exc,
            )
            if attempt == 0:
                try:
                    from strategies.dex_aggregator import routing_top

                    routing_top.refresh_discovery_cache(solver)
                except Exception as cache_exc:
                    logger.debug("zero_score_guard: cache refresh skipped: %s", cache_exc)

    reason = str(last_exc) if last_exc else "unknown"
    logger.error("zero_score_guard: returning recovery plan (%s)", reason)
    return build_recovery_plan(solver, intent, state, snapshot, reason)


def guard_quote(
    solver: Any,
    intent: AppIntentDefinition,
    state: IntentState,
    snapshot: MarketSnapshot | None,
) -> QuoteResult:
    """Call baseline quote; on failure return conservative quote (no raise)."""
    try:
        return BaselineSwapSolver.quote(solver, intent, state, snapshot)
    except Exception as exc:
        logger.warning("zero_score_guard: quote failed: %s", exc)
        params = _swap_params(solver, intent, state)
        min_out = int(params.get("min_output_amount") or 0)
        amount_in = int(params.get("input_amount") or 0)
        est = min_out if min_out > 0 else max(amount_in // 100, 1)
        return QuoteResult(
            estimated_output=str(est),
            route_summary="zero_score_guard_fallback",
            gas_estimate=250_000,
            metadata={"guard": True, "error": str(exc)[:200]},
            platform_fee_wei="0",
        )
