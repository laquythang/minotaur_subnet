# Logic Miner Top — Chiến lược solver điểm cao

Tài liệu này tổng hợp phân tích từ `dev_miner.md`, `docs/miner/custom-solver.md`, `docs/solver/solver_guide.md` và code harness. Làm **tuần tự từng bước**; mỗi bước có checkpoint trước khi sang bước tiếp.

---

## 1. Phân tích: điểm cao đến từ đâu?

### 1.1 Công thức chấm điểm (ưu tiên)

| Thứ tự | Tiêu chí | Hàm ý thực tế |
|--------|----------|---------------|
| 1 | **User surplus** | Output token nhiều hơn, vẫn ≥ `minOut` |
| 2 | Correctness + gas + không revert | Plan hợp lệ, simulate on-chain pass |
| 3 | Protocol fee | Chỉ tie-break |

Benchmark tổng hợp:

```
40% synthetic scenarios + 60% historical (swap thật từ aggregator)
```

Adopt champion: challenger phải **≥ champion + 0.5%** (`DETHRONE_MARGIN`), pass **cả JS score và on-chain simulation**.

### 1.2 Ràng buộc runtime (không được vi phạm)

| Ràng buộc | Impact nếu vi phạm |
|-----------|-------------------|
| Docker `--network=none` | Không gọi API/RPC bên ngoài lúc benchmark production |
| Read-only FS | Không ghi file runtime |
| Timeout 30s/plan | Exception hoặc kill → **0 điểm** |
| `intent_id` = `app_id`, interactions non-empty | Plan invalid → 0 |
| `quoted_output` đúng khi cần | Revert on-chain → 0 |

**Kết luận:** Trước khi tối ưu giá, phải **không bao giờ 0 điểm**. Sau đó mới cạnh tranh surplus.

### 1.3 Baseline champion hiện tại

Repo `minotaur-solver` (`strategies/dex_aggregator/baseline_solver.py`):

- Uniswap V3 + Aerodrome Slipstream trên Base (8453)
- Multi-hop qua WETH, USDC
- RPC-first pool discovery, fallback snapshot
- Factory fee tiers: 100, 500, 3000, 10000

Để **vượt 0.5%**, cần cải thiện **output thực** trên cùng scenario set — không chỉ sửa metadata.

### 1.4 Lever tối ưu (theo impact / effort)

| # | Lever | Impact | Effort | File sửa (chỉ extension) |
|---|-------|--------|--------|---------------------------|
| 1 | Verify pipeline local | Tránh lãng phí thời gian | Thấp | `solver.py`, script test |
| 2 | Zero-score guard | Cao (tránh 0) | Thấp | `solver.py` wrapper |
| 3 | Pool discovery rộng hơn | Trung bình–cao | Trung bình | `strategies/dex_aggregator/` hoặc subclass |
| 4 | Cross-DEX (Sushi, Curve, …) | Cao | Cao | Module mới trong `strategies/` |
| 5 | Split routing (order lớn) | Cao với size lớn | Cao | Override `generate_plan` |
| 6 | Offline pool bundle | Bắt buộc cho prod offline | Trung bình | Data file + load trong `initialize` |
| 7 | Gas / ít hop | Thấp–trung bình | Thấp | Route selection logic |

### 1.5 Nguyên tắc sửa code (sync upstream dễ)

**CHỈ sửa:**

- `minotaur-solver/solver.py` — entry point miner (`SOLVER_CLASS`)
- `minotaur-solver/strategies/dex_aggregator/*_top.py` — module mới (nếu cần)
- `minotaur_subnet/scripts/local_miner_*.sh` — script test local
- `minotaur_subnet/logic_miner_top.md` — tài liệu này

**KHÔNG sửa** (tránh conflict khi `git merge upstream`):

- `strategies/dex_aggregator/baseline_solver.py` và file upstream khác
- Comment/docstring trong file owner
- `minotaur_subnet/` core trừ script riêng

Pattern: **kế thừa + override**, không fork-sửa baseline.

```python
# solver.py — extension point duy nhất bắt buộc
class MinerSolver(BaselineSwapSolver):
    def generate_plan(self, intent, state, snapshot=None):
        return super().generate_plan(intent, state, snapshot)  # step 1
        # step 2+: wrap với guard; step 3+: gọi custom router
```

---

## 2. Các bước thực thi

### Bước 1 — Baseline pipeline local (thực thi trước)

**Mục tiêu:** Miner chạy được local, pass screening + Docker smoke, **(khuyến nghị)** có điểm bench A/B vs genesis làm mốc.

Bước 1 chia **2 mức** — làm đủ **Mức B** trước khi sang Bước 2:

| Mức | Nội dung | Bắt buộc? |
|-----|----------|-----------|
| **A — Tối thiểu** | Screening + Docker + import solver | ✅ Có thể sang Bước 2 |
| **B — Đầy đủ** | Thêm `scoring_lab bench --limit 3` | ⭐ Khuyến nghị (có baseline score) |

---

#### 1.0 — Chuẩn bị trước khi chạy script

**Phần mềm (một lần):**

```bash
python3 --version    # >= 3.12
docker --version
git --version
```

| Công cụ | Mục đích | Kiểm tra |
|---------|----------|----------|
| Python 3.12+ venv | SDK + scoring_lab | `source minotaur_subnet/.venv/bin/activate` |
| Docker | Build solver giống validator | `docker ps` |
| Repo `minotaur-solver` | Code solver | `ls /root/minotaur-solver/solver.py` |
| **Foundry (`anvil`)** | Fork Base cho bench | `anvil --version` |

**Cài Foundry (nếu thiếu `anvil`):**

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
export PATH="$HOME/.foundry/bin:$PATH"
# Thêm dòng PATH trên vào ~/.bashrc để không mất sau logout
```

> Script `local_miner_step1.sh` **tự thêm** `$HOME/.foundry/bin` vào PATH nếu `anvil` đã cài nhưng shell chưa có. Nếu vẫn báo thiếu `anvil` → chưa cài Foundry, chạy lệnh trên.

**Alchemy RPC (cho bench + testnet sau này):**

> ⚠️ Key đặt trong file **`.env`**, **KHÔNG** sửa `.env.example` (file example không được script đọc).

```bash
cd minotaur_subnet/platform/local_testnet
cp .env.example .env
nano .env   # hoặc editor khác
```

Sửa **2 dòng** (cùng 1 API key Alchemy free tier):

```bash
ALCHEMY_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/<API_KEY>
BASE_ALCHEMY_RPC_URL=https://base-mainnet.g.alchemy.com/v2/<API_KEY>
```

Lấy key: https://www.alchemy.com/

**Cách script đọc RPC:**

- Tự load `platform/local_testnet/.env` nếu chưa `export`, **hoặc**
- Export trước khi chạy:

```bash
export BASE_ALCHEMY_RPC_URL="https://base-mainnet.g.alchemy.com/v2/<API_KEY>"
```

**Repo solver (trong cùng fork `minotaur_subnet`):**

```bash
cd ~/minotaur_subnet
./scripts/setup_miner_solver.sh   # bootstrap miner_solver/ nếu chưa có
# Code miner: ~/minotaur_subnet/miner_solver/
```

Chỉ sửa **`miner_solver/solver.py`** và các module `*_top.py` (extension point):

- `MinerSolver` kế thừa `BaselineSwapSolver`
- `SOLVER_CLASS = MinerSolver`
- Metadata: `my-solver` v0.1.0
- **Không** sửa `baseline_solver.py` hay file upstream khác

---

#### 1.1 — Chạy script verify

```bash
export PATH="$HOME/.foundry/bin:$PATH"   # nếu vừa cài Foundry
cd ~/minotaur_subnet && source .venv/bin/activate
./scripts/local_miner_step1.sh
```

Script thực hiện tuần tự:

1. Kiểm tra file bắt buộc (`Dockerfile`, `solver.py`, `README.md`)
2. Load `.env` → lấy `BASE_ALCHEMY_RPC_URL`
3. Screening stage 1 (static checks)
4. `docker build --network=none`
5. Docker smoke: import `SOLVER_CLASS`, `initialize`, `metadata()`
6. *(Nếu đủ RPC + anvil)* `scoring_lab bench --limit 3`

---

#### 1.2 — Checkpoint

**Mức A (tối thiểu):**

- [ ] Screening stage 1: `[screening stage 1] PASSED: True`
- [ ] `[docker] building with --network=none` thành công
- [ ] In ra `class: MinerSolver` + metadata `my-solver`
- [ ] Image Docker: `my-solver:local`

**Mức B (đầy đủ — khuyến nghị):**

- [ ] Thấy dòng `[env] loading BASE_ALCHEMY_RPC_URL from .../.env`
- [ ] **Không** thấy `[skip] scoring_lab bench`
- [ ] Thấy `[optional] scoring_lab bench (limit 3) ...`
- [ ] In điểm **genesis** vs **candidate** + verdict adoption
- [ ] Ghi lại `global_score` candidate làm **baseline mốc** trước Bước 2

**Output:** Docker image `my-solver:local` + (nếu Mức B) số điểm bench ban đầu.

---

#### 1.3 — Lỗi thường gặp ở Bước 1

| Triệu chứng | Nguyên nhân | Cách fix |
|-------------|-------------|----------|
| `[skip] scoring_lab bench — thiếu: BASE_ALCHEMY_RPC_URL` | Chưa có `.env` hoặc chưa export | Tạo `platform/local_testnet/.env` (không phải `.env.example`) |
| `[skip] ... thiếu: anvil` | Chưa cài Foundry **hoặc** chưa có trong PATH | `foundryup`; script tự thêm `~/.foundry/bin` — nếu vẫn lỗi thì cài lại Foundry |
| `no app contract: resolve from the AppRegistry` | Bench thiếu địa chỉ DexAggregator trên Base | Script truyền `--contract 0x0AeA6Ab70B384ADC6493d40e927ce53A7cefE035` (hoặc set `SCORING_LAB_DEX_CONTRACT` trong `.env`) |
| `dex scorer not found` | Thiếu file JS scoring | Script tự tải từ API production → `scripts/fixtures/dex_aggregator_scoring.js`; hoặc set `MINOTAUR_DEX_SCORER` |
| `WARN: ... still contains placeholder YOUR_KEY` | Key chưa thay trong `.env` | Sửa `YOUR_KEY` → API key thật |
| Key trong `.env.example` nhưng vẫn skip | Script không đọc `.example` | `cp .env.example .env` rồi sửa `.env` |
| `solver repo not found` | Chưa bootstrap | `./scripts/setup_miner_solver.sh` |
| `docker build` fail | Thiếu base image / Dockerfile sai | Kiểm tra `FROM ghcr.io/subnet112/solver-base:v1`, không có CMD/ENTRYPOINT |
| Bench fail sau khi chạy | RPC lỗi / app registry | Kiểm tra key Alchemy, network; xem log `WARN: bench failed` |
| `scoreIntent simulation reverted`, `on_chain=—`, score 0 | Lab fork / APP-mode fee path (genesis **và** candidate cùng 0) | **Không phải lỗi solver** — pipeline vẫn OK; dùng `make testnet-up` (Bước 6) cho sim đầy đủ |
| `GENERATE_PLAN timed out` | Cold pool discovery > 30s | Script bench đã tăng timeout 90s qua `local_miner_common.sh` |

---

#### 1.4 — Verify thủ công (nếu cần debug từng phần)

```bash
# Chỉ screening stage 1
python -c "
from minotaur_subnet.harness.screening import run_stage_1
r = run_stage_1('~/minotaur_subnet/miner_solver')
print('PASSED:', r.passed, r.details)
"

# Bench riêng (sau khi có RPC + anvil)
export MINOTAUR_SOLVER_OSS=~/minotaur_subnet/miner_solver
export BASE_ALCHEMY_RPC_URL=...   # hoặc đã có trong .env
python -m minotaur_subnet.harness.scoring_lab bench \
  --candidate ~/minotaur_subnet/miner_solver/solver.py \
  --limit 3
```

> **Lưu ý:** Submit local testnet (`make testnet-up` + `miner.main submit`) thuộc **Bước 6**, không phải Bước 1. Bước 1 chỉ cần script + bench tùy chọn.

---

### Bước 2 — Zero-score guard

**Mục tiêu:** Không exception, plan luôn structurally valid.

**Logic trong `solver.py`:**

- try/except quanh `super().generate_plan()` → log, fallback plan an toàn nếu có thể
- Validate: `intent_id`, `interactions`, `deadline`, address format
- Không raise ra ngoài

**Test:** `scoring_lab bench --limit 10` — không scenario nào error/0 do exception.

---

### Bước 3 — Pool discovery mở rộng

**Mục tiêu:** Không bỏ sót pool liquidity tốt (thêm fee tier / token trung gian).

**Cách:** Tạo `strategies/dex_aggregator/routing_top.py` (file mới), subclass hoặc wrap processor; **không sửa** `baseline_solver.py`.

**Test:** So sánh surplus từng scenario vs genesis trên bench.

---

### Bước 4 — Cross-DEX

**Mục tiêu:** Thêm venue (SushiSwap V2/V3, Curve stable, …) trên Base.

**Cách:** Module `strategies/dex_aggregator/extra_dex_top.py` + quote aggregator; bundle router/factory address trong repo.

**Test:** `--limit 20` bench; margin trung bình vs genesis.

---

### Bước 5 — Split routing

**Mục tiêu:** Order lớn → chia nhiều pool, giảm price impact.

**Cách:** Override route selection khi `input_amount > threshold`.

---

### Bước 6 — Vòng lặp bench + submit

```bash
# Bench nhanh
export MINOTAUR_SOLVER_OSS=/root/minotaur-solver
export BASE_ALCHEMY_RPC_URL=https://base-mainnet.g.alchemy.com/v2/KEY
python -m minotaur_subnet.harness.scoring_lab bench \
  --candidate /root/minotaur-solver/solver.py --limit 10

# Full testnet (cần .env + make testnet-up)
make testnet-up
python -m minotaur_subnet.miner.main submit \
  --repo-url https://github.com/<user>/minotaur-solver \
  --commit-hash $(git -C /root/minotaur-solver rev-parse HEAD) \
  --hotkey default --validator-url http://localhost:8080 --poll
```

**Checkpoint adopt local:** `benchmark_score` ≥ champion + 0.5%.

---

### Bước 7 — Mainnet

Register subnet 112 → submit `https://api.minotaursubnet.com` → monitor `/v1/solver/champion`.

---

## 3. Tooling local

| Tool | Mục đích |
|------|----------|
| `./scripts/local_miner_run_all.sh` | Chạy tuần tự Bước 1 → 6 |
| `./scripts/local_miner_step1.sh` | Bước 1: screening + Docker + bench (auto-load `.env`) |
| `./scripts/local_miner_step2.sh` | Bước 2: zero-score guard unit test + bench |
| `./scripts/local_miner_step3.sh` | Bước 3: routing_top pool discovery |
| `./scripts/local_miner_step4.sh` | Bước 4: extra_dex_top (Pancake V3 Base) |
| `./scripts/local_miner_step5.sh` | Bước 5: split_routing_top threshold |
| `./scripts/local_miner_step6.sh` | Bước 6: bench loop + testnet submit (optional) |
| `./scripts/setup_solver_github.sh` | Kiểm tra / gắn origin solver fork trên GitHub |
| `scoring_lab bench` | A/B genesis vs candidate (cần Base RPC + anvil) |
| `make testnet-up` | Full pipeline submit → scored (Bước 6) |
| `run_stage_1(path)` | Chỉ kiểm tra file |

Env / file quan trọng (Bước 1):

```bash
# Repo paths
export MINOTAUR_SOLVER_REPO=/root/minotaur-solver
export MINOTAUR_SOLVER_OSS=/root/minotaur-solver   # scoring_lab genesis path

# RPC — một trong hai cách:
# (1) File .env (khuyến nghị):
#    minotaur_subnet/platform/local_testnet/.env
#    → ALCHEMY_RPC_URL + BASE_ALCHEMY_RPC_URL
# (2) Export trực tiếp:
export BASE_ALCHEMY_RPC_URL=https://base-mainnet.g.alchemy.com/v2/<API_KEY>

# Foundry (bắt buộc cho bench)
export PATH="$HOME/.foundry/bin:$PATH"

# Bench scoring_lab (tùy chọn — script tự set default nếu thiếu)
# SCORING_LAB_DEX_CONTRACT=0x0AeA6Ab70B384ADC6493d40e927ce53A7cefE035  # Base DexAggregatorApp
# MINOTAUR_DEX_SCORER=scripts/fixtures/dex_aggregator_scoring.js       # auto-fetched lần đầu
```

## 4. Tiến độ

| Bước | Trạng thái | Ghi chú |
|------|------------|---------|
| 1 Baseline pipeline local | ✅ | `local_miner_step1.sh` — Mức A OK; Mức B bench có thể 0 nếu scoreIntent revert trên fork |
| 2 Zero-score guard | ✅ | `zero_score_guard_top.py` + `local_miner_step2.sh` |
| 3 Pool discovery | ✅ | `routing_top.py` + `local_miner_step3.sh` |
| 4 Cross-DEX | ✅ | `extra_dex_top.py` (Pancake V3 Base) + `local_miner_step4.sh` |
| 5 Split routing | ✅ | `split_routing_top.py` + `local_miner_step5.sh` |
| 6 Bench + submit | ✅ | `local_miner_step6.sh` — cần `make testnet-up` + `MINER_GITHUB_REPO_URL` để submit |
| 7 Mainnet | ⬜ | Thủ công — xem § Bước 7 |

**Solver modules (chỉ extension):**

| File | Vai trò |
|------|---------|
| `miner_solver/solver.py` | `MinerSolver` — wiring steps 2–5 |
| `miner_solver/strategies/dex_aggregator/zero_score_guard_top.py` | Bước 2 |
| `miner_solver/strategies/dex_aggregator/routing_top.py` | Bước 3 |
| `miner_solver/strategies/dex_aggregator/extra_dex_top.py` | Bước 4 |
| `miner_solver/strategies/dex_aggregator/split_routing_top.py` | Bước 5 |

**GitHub (laquythang — một fork duy nhất):**

| Repo | URL | Dùng cho |
|------|-----|----------|
| `minotaur_subnet` | https://github.com/laquythang/minotaur_subnet | SDK + `miner_solver/` + scripts |
| branch `miner-solver` | cùng repo | **Submit miner** — `./scripts/publish_miner_solver.sh` |

Commit code miner:
```bash
cd ~/minotaur_subnet
git add miner_solver/solver.py miner_solver/strategies/dex_aggregator/*_top.py
git commit -m "miner: routing extensions"
git push origin develop
./scripts/publish_miner_solver.sh
```

Cấu hình: `scripts/miner_github.env` (auto-load bởi `local_miner_common.sh`).

```bash
export PATH="$HOME/.foundry/bin:$PATH"
cd ~/minotaur_subnet && source .venv/bin/activate
chmod +x scripts/local_miner_*.sh scripts/setup_miner_solver.sh scripts/publish_miner_solver.sh
./scripts/local_miner_run_all.sh
```
