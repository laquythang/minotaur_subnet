# Hướng dẫn từng bước: Người mới → Miner hiệu suất cao

Lộ trình thực hành cho người mới trên Minotaur Subnet 112. Làm **tuần tự từng giai đoạn**, chỉ chuyển bước khi đạt **Checkpoint** của giai đoạn đó.

---

## Tổng quan: Bạn đang làm gì?

Miner Minotaur **không** chạy server 24/7. Bạn:

1. Viết **solver** (code tạo kế hoạch swap tốt nhất)
2. Đóng gói trong **Docker**
3. **Submit** lên API của subnet
4. Validator benchmark → nếu điểm **cao hơn champion ≥ 0.5%** → bạn trở thành champion → nhận emission

```
Bạn viết code → Submit → Validator chạy benchmark → Champion nhận 100% emission
```

---

## Giai đoạn 0: Chuẩn bị môi trường (1–2 giờ)

### Bước 0.1 — Cài phần mềm

| Công cụ | Phiên bản | Mục đích |
|---------|-----------|----------|
| Python | 3.12+ | Chạy CLI miner, test local |
| Docker | Mới nhất | Build solver, chạy testnet |
| Git | — | Quản lý repo solver |
| `btcli` | Bittensor CLI | Đăng ký subnet mainnet |
| (Tùy chọn) Alchemy account | Free tier | Fork Base mainnet khi test |

Kiểm tra:

```bash
python3 --version    # >= 3.12
docker --version
git --version
btcli --version      # chỉ cần khi lên mainnet
```

### Bước 0.2 — Clone repo subnet (SDK + testnet)

Repo này **chỉ** dùng để dev/test — **không** chứa code solver submit (trừ skeleton `docker/example-solver/`).

```bash
# Fork trên GitHub: subnet112/minotaur_subnet → <your-user>/minotaur_subnet (khuyến nghị)
git clone https://github.com/<your-user>/minotaur_subnet.git
cd minotaur_subnet
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

**Checkpoint:** `python -c "import minotaur_subnet; print('OK')"` in ra `OK`.

> **Hai repo trên máy:** `minotaur_subnet` và `minotaur-solver` là **hai thư mục Git riêng**, cùng cấp (ví dụ `~/minotaur_subnet` và `~/minotaur-solver`). Chi tiết: [fork_and_update_owner_code.md §2](./fork_and_update_owner_code.md#2-hai-repo-hai-thư-mục-độc-lập-trên-máy).

---

## Giai đoạn 1: Hiểu cách chấm điểm (30 phút đọc)

Đọc kỹ trước khi code — đây là thứ quyết định “hiệu suất cao”.

### Điểm được tính thế nào?

| Thứ tự | Tiêu chí |
|--------|----------|
| 1 | **User surplus** — user nhận nhiều token hơn, vẫn đạt `minOut` |
| 2 | Đúng logic, ít gas, không revert |
| 3 | Protocol fee (chỉ dùng khi hòa điểm) |

### Công thức benchmark

```
Điểm tổng = 40% synthetic scenarios + 60% historical (swap thật từ aggregator)
```

### Điều kiện thắng champion

- Phải vượt champion **ít nhất 0.5%** (`DETHRONE_MARGIN`)
- Plan phải pass **cả** JS score **và** on-chain simulation
- `generate_plan()` lỗi / revert → **điểm 0**

### Ràng buộc khi chạy trên validator

Solver chạy trong Docker:

- **Không có internet** (`--network=none`)
- Filesystem **read-only**
- Tối đa **30 giây** mỗi plan
- Mọi dữ liệu routing/pool phải **bundle sẵn** trong image

---

## Giai đoạn 2: Tạo repo solver của bạn (1–2 giờ)

### Bước 2.1 — Fork trên GitHub, rồi clone từ fork của bạn

Repo production dùng cho miner:

**Upstream (owner):** https://github.com/subnet112/minotaur-solver

**Quy trình khuyến nghị:**

1. Trên GitHub: **Fork** `subnet112/minotaur-solver` → `<your-user>/minotaur-solver` (repo **public**).
2. Trên máy: **clone từ fork của bạn** (không clone thẳng `subnet112` nếu bạn cần push/submit).

```bash
# Ví dụ: laquythang — thay bằng username GitHub của bạn
git clone https://github.com/laquythang/minotaur-solver.git ~/minotaur-solver
cd ~/minotaur-solver

# Remote upstream (owner) — dùng khi sync code mới
git remote add upstream https://github.com/subnet112/minotaur-solver.git
git remote -v
```

**Cấu trúc trên máy sau khi clone cả hai repo:**

```
~/minotaur_subnet/          ← SDK, scripts, local testnet (Giai đoạn 0)
~/minotaur-solver/          ← code miner submit (Giai đoạn 2+) — NGOÀI project subnet
```

Repo solver có:

- `strategies/dex_aggregator/baseline_solver.py` — engine routing baseline (champion)
- `strategies/` — strategy theo từng app
- `solver.py` + `Dockerfile` + `README.md` — bắt buộc khi submit

> **Chi tiết fork / sync upstream:** [fork_and_update_owner_code.md](./fork_and_update_owner_code.md)

> Skeleton `minotaur_subnet/docker/example-solver/` chỉ để tham khảo — **không đủ** để cạnh tranh. Dùng repo [`minotaur-solver`](https://github.com/subnet112/minotaur-solver) riêng.

### Bước 2.2 — Trỏ scripts test về repo solver (ngoài project)

Scripts `scripts/local_miner_step*.sh` chạy **từ** `minotaur_subnet` nhưng đọc solver **từ** `~/minotaur-solver`:

```bash
export MINOTAUR_SOLVER_REPO=~/minotaur-solver
# hoặc thêm vào ~/.bashrc để không phải gõ lại
```

Kiểm tra:

```bash
cd ~/minotaur_subnet && source .venv/bin/activate
echo "solver: $MINOTAUR_SOLVER_REPO"
ls "$MINOTAUR_SOLVER_REPO/solver.py"
```

**Checkpoint:** File `~/minotaur-solver/solver.py` tồn tại; `MINOTAUR_SOLVER_REPO` trỏ đúng path.

### Bước 2.3 — Cấu trúc repo solver bắt buộc

```
~/minotaur-solver/
├── Dockerfile          # FROM ghcr.io/subnet112/solver-base:v1
├── solver.py           # export SOLVER_CLASS = ...
├── requirements.txt    # (optional) — phải vendor wheel nếu cần dep mới
├── README.md           # mô tả approach của bạn
└── strategies/         # logic routing theo app
```

### Bước 2.4 — Dockerfile tối thiểu

```dockerfile
FROM ghcr.io/subnet112/solver-base:v1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt 2>/dev/null || true

COPY . /app
WORKDIR /app

# KHÔNG thêm CMD hoặc ENTRYPOINT
```

### Bước 2.5 — `solver.py` khung cơ bản

Bắt đầu bằng cách **kế thừa baseline**, không viết từ đầu:

```python
from strategies.dex_aggregator.baseline_solver import BaselineSwapSolver
from minotaur_subnet.sdk.intent_solver import SolverMetadata

class MySwapSolver(BaselineSwapSolver):
    def metadata(self) -> SolverMetadata:
        base = super().metadata()
        return SolverMetadata(
            name="my-solver",
            version="0.1.0",
            author="your-name",
            description="Improved cross-DEX routing on Base",
            supported_chains=base.supported_chains,
            supported_intent_types=base.supported_intent_types,
        )

    # Bước đầu: dùng baseline nguyên bản để verify pipeline
    # Sau đó override generate_plan() để cải thiện routing

SOLVER_CLASS = MySwapSolver
```

**Checkpoint:** File `solver.py` có `SOLVER_CLASS` ở cuối file.

---

## Giai đoạn 3: Test local không cần mainnet (2–4 giờ)

> **Hai repo:** Lệnh test chạy từ `~/minotaur_subnet`; code solver nằm ở `~/minotaur-solver` (ngoài project). Luôn `export MINOTAUR_SOLVER_REPO=~/minotaur-solver` trước khi dùng scripts.

### Bước 3.0 — Pipeline nhanh với `local_miner_step*.sh` (khuyến nghị)

Sau khi clone cả hai repo và cấu hình `.env` (mục 3.1):

```bash
export MINOTAUR_SOLVER_REPO=~/minotaur-solver
export PATH="$HOME/.foundry/bin:$PATH"

cd ~/minotaur_subnet
source .venv/bin/activate
chmod +x scripts/local_miner_*.sh scripts/sync_minotaur_solver_upstream.sh

./scripts/local_miner_step1.sh   # screening + Docker build + bench smoke
./scripts/local_miner_step2.sh   # zero-score guard (unit test)
# ... step 3–6 tuần tự, hoặc:
./scripts/local_miner_run_all.sh   # chạy step 1–6
```

Script tự load `platform/local_testnet/.env` (RPC Base) và dùng `$MINOTAUR_SOLVER_REPO` làm path solver.

Cấu hình GitHub submit (sửa username trong file):

```bash
# scripts/miner_github.env — ví dụ:
export MINER_GITHUB_REPO_URL=https://github.com/laquythang/minotaur-solver
```

Push solver rồi submit (không cần `publish_miner_solver.sh` khi dùng repo solver riêng):

```bash
cd ~/minotaur-solver
git add solver.py strategies/
git commit -m "miner: routing improvements"
git push origin main
```

### Bước 3.1 — Khởi động local testnet

```bash
cd minotaur_subnet   # repo chính
source .venv/bin/activate

cd platform/local_testnet
cp .env.example .env
```

Sửa `.env`, thêm RPC (Alchemy free tier):

```bash
ALCHEMY_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
BASE_ALCHEMY_RPC_URL=https://base-mainnet.g.alchemy.com/v2/YOUR_KEY
```

Khởi động:

```bash
cd ../..   # về root minotaur_subnet
make testnet-up
```

Đợi ~2–5 phút, kiểm tra:

```bash
curl http://localhost:8080/health
```

Kỳ vọng: JSON với `"status": "ok"` hoặc tương tự.

### Bước 3.2 — Test Docker build (giống validator)

Trong repo solver (**ngoài** `minotaur_subnet`):

```bash
cd ~/minotaur-solver

docker build --network=none --memory=4g -t my-solver:local .

docker run --rm --network=none --read-only \
  --tmpfs=/tmp:size=64m --memory=2g --cpus=1.0 \
  --entrypoint python my-solver:local \
  -c "from solver import SOLVER_CLASS; s=SOLVER_CLASS(); s.initialize({'chain_ids':[8453]}); print(s.metadata())"
```

Hoặc từ subnet (dùng cùng image tag với scripts):

```bash
export MINOTAUR_SOLVER_REPO=~/minotaur-solver
cd ~/minotaur_subnet && source .venv/bin/activate
./scripts/local_miner_step1.sh
```

**Checkpoint:** Build thành công, in ra metadata solver.

### Bước 3.3 — Screening stage 1 (kiểm tra file)

Từ repo `minotaur_subnet` (solver path trỏ ra ngoài):

```bash
export MINOTAUR_SOLVER_REPO=~/minotaur-solver
cd ~/minotaur_subnet && source .venv/bin/activate

python -c "
from minotaur_subnet.harness.screening import run_stage_1
r = run_stage_1('$MINOTAUR_SOLVER_REPO')
print('PASSED:', r.passed)
print(r.details)
"
```

**Checkpoint:** `PASSED: True`

### Bước 3.4 — Submit thử lên local API

Local testnet tự đăng ký test miner — không cần TAO. **Push commit lên fork GitHub trước** — validator clone repo, không đọc file local.

```bash
export MINOTAUR_SOLVER_REPO=~/minotaur-solver
export VALIDATOR_URL=http://localhost:8080
export MINER_GITHUB_REPO_URL=https://github.com/<your-user>/minotaur-solver

cd ~/minotaur-solver
git push origin main

cd ~/minotaur_subnet && source .venv/bin/activate

python -m minotaur_subnet.miner.main submit \
  --repo-url "$MINER_GITHUB_REPO_URL" \
  --commit-hash $(git -C ~/minotaur-solver rev-parse HEAD) \
  --hotkey default \
  --validator-url $VALIDATOR_URL \
  --poll
```

Hoặc sau `make testnet-up`:

```bash
source scripts/miner_github.env
export MINOTAUR_SOLVER_REPO=~/minotaur-solver
./scripts/local_miner_step6.sh
```

Theo dõi status:

```
queued → screening_stage_1 → screening_stage_2 → screening_stage_3
       → benchmarking → scored → adopted / rejected
```

**Checkpoint lần đầu:** Đạt `scored` (dù chưa adopt cũng được — quan trọng là pipeline chạy được).

### Bước 3.5 — Xem điểm benchmark

```bash
python -m minotaur_subnet.miner.main status \
  --submission-id sub_xxx \
  --validator-url http://localhost:8080
```

Ghi lại `benchmark_score` — đây là baseline của bạn trước khi tối ưu.

---

## Giai đoạn 4: Benchmark nhanh với Scoring Lab (không cần full testnet)

Tool so sánh solver của bạn vs genesis champion trên Base fork:

```bash
export MINOTAUR_SOLVER_REPO=~/minotaur-solver
cd ~/minotaur_subnet
source .venv/bin/activate

# RPC: export hoặc đặt trong platform/local_testnet/.env
export BASE_ALCHEMY_RPC_URL=https://base-mainnet.g.alchemy.com/v2/YOUR_KEY
export PATH="$HOME/.foundry/bin:$PATH"

# Cách 1 — script wrapper (timeout bench đã tăng)
./scripts/local_miner_step2.sh   # bench --limit 10

# Cách 2 — scoring_lab trực tiếp
python -m minotaur_subnet.harness.scoring_lab bench \
  --base-rpc $BASE_ALCHEMY_RPC_URL \
  --candidate ~/minotaur-solver/solver.py \
  --limit 5
```

Kết quả in ra:

- Điểm **genesis** (champion hiện tại)
- Điểm **candidate** (solver của bạn)
- Verdict: có đủ điều kiện adopt không (margin 0.5%)

**Checkpoint:** Hiểu output; biết solver đang thua hay thắng genesis trên vài scenario.

---

## Giai đoạn 5: Cải thiện solver — phần quan trọng nhất

Baseline đã có: Uniswap V3 + Aerodrome Slipstream trên Base, multi-hop qua WETH. Để **hiệu suất cao**, tập trung theo thứ tự:

### Bước 5.1 — Đảm bảo không bị điểm 0

Trước khi tối ưu giá, fix các lỗi cơ bản:

- [ ] `intent_id` trong `ExecutionPlan` khớp `intent.app_id`
- [ ] `interactions` không rỗng
- [ ] Address dạng `0x` + 40 hex chars
- [ ] `deadline` > thời điểm hiện tại
- [ ] Không raise exception trong `generate_plan()`
- [ ] Có `quoted_output` khi scenario yêu cầu (tránh on-chain revert)

### Bước 5.2 — Cải thiện routing (theo impact)

| # | Cải tiến | Tại sao |
|---|----------|---------|
| 1 | **Cross-DEX** — thêm SushiSwap, Curve, Balancer | Giá tốt hơn single DEX |
| 2 | **Split routing** — chia order lớn nhiều pool | Giảm price impact |
| 3 | **Pool discovery rộng hơn** — scan thêm fee tiers | Không bỏ sót pool liquidity tốt |
| 4 | **Gas optimization** — ít hop, calldata nhỏ | Điểm phụ nhưng có thể quyết định khi hòa |
| 5 | **Bundle offline data** — pool list, routing table trong image | Solver chạy được khi không có internet |

### Bước 5.3 — Vòng lặp cải thiện

```
1. Sửa ~/minotaur-solver/solver.py hoặc strategies/
2. export MINOTAUR_SOLVER_REPO=~/minotaur-solver
3. cd ~/minotaur_subnet && ./scripts/local_miner_step1.sh   # hoặc scoring_lab bench
4. git push origin main → submit local testnet (step 6)
5. Lặp lại
```

Mục tiêu local: điểm **> champion + 0.5%** trước khi lên mainnet (để có buffer cho shadow cases ẩn trên production).

### Bước 5.4 — Dùng `RoutingSolver` khi có nhiều app

```python
from minotaur_subnet.sdk.routing_solver import RoutingSolver
from strategies.dex_aggregator.my_swap_strategy import MySwapStrategy

class MySolver(RoutingSolver):
    def initialize(self, config):
        super().initialize(config)
        self.register_strategy(MySwapStrategy())

SOLVER_CLASS = MySolver
```

---

## Giai đoạn 6: Lên mainnet (khi local ổn định)

### Bước 6.1 — Tạo Bittensor wallet

```bash
btcli wallet new_coldkey --wallet.name my-miner
btcli wallet new_hotkey --wallet.name my-miner --wallet.hotkey my-miner-hotkey
```

### Bước 6.2 — Nạp TAO và đăng ký subnet 112

```bash
btcli wallet balance --wallet.name my-miner --subtensor.network finney

btcli subnet register --netuid 112 --subtensor.network finney \
  --wallet.name my-miner --wallet.hotkey my-miner-hotkey
```

Xác nhận trong metagraph:

```bash
btcli subnet metagraph --netuid 112 --subtensor.network finney
```

### Bước 6.3 — Submit production

```bash
export VALIDATOR_URL=https://api.minotaursubnet.com
export MINER_GITHUB_REPO_URL=https://github.com/<your-user>/minotaur-solver

# Push commit mới lên fork GitHub trước
cd ~/minotaur-solver
git add . && git commit -m "v0.2: improved cross-DEX routing" && git push origin main

cd ~/minotaur_subnet
source .venv/bin/activate

python -m minotaur_subnet.miner.main submit \
  --repo-url "$MINER_GITHUB_REPO_URL" \
  --commit-hash $(git -C ~/minotaur-solver rev-parse HEAD) \
  --hotkey my-miner-hotkey \
  --validator-url $VALIDATOR_URL \
  --poll
```

**Checkpoint:** Status `adopted` = bạn là champion.

---

## Giai đoạn 7: Duy trì vị trí champion

### Monitor

```bash
# Champion hiện tại
curl https://api.minotaursubnet.com/v1/solver/champion

# Round đang mở
curl https://api.minotaursubnet.com/v1/solver/round

# Status submission
python -m minotaur_subnet.miner.main status \
  --submission-id sub_xxx \
  --validator-url https://api.minotaursubnet.com
```

### Khi nào submit lại?

- Có challenger mới với điểm cao hơn bạn
- Bạn cải thiện solver và scoring_lab cho thấy margin ≥ 0.5%
- App mới được deploy trên network

### (Tùy chọn) Agent loop tự động

Nếu có **Claude CLI** + subscription:

```bash
# Local testnet
make miner-agent

# Hoặc production
python -m minotaur_subnet.miner.main agent \
  --validator-url https://api.minotaursubnet.com \
  --strategy-dir ./strategies \
  --miner-id my-miner-001
```

Agent tự discover app → generate strategy → test → submit. `cost_gate` tự dừng khi đã là champion hoặc hết budget token.

---

## Checklist tổng hợp

```
□ Cài Python 3.12+, Docker, Git, Foundry (anvil) cho bench
□ Clone minotaur_subnet (fork) + pip install + .venv
□ Fork minotaur-solver trên GitHub → clone ~/minotaur-solver
□ git remote add upstream (subnet112/minotaur-solver)
□ export MINOTAUR_SOLVER_REPO=~/minotaur-solver
□ solver.py kế thừa BaselineSwapSolver + SOLVER_CLASS
□ ./scripts/local_miner_step1.sh → screening + Docker OK
□ make testnet-up + submit local → scored
□ scoring_lab bench → biết điểm vs genesis
□ Cải thiện routing → điểm local > champion + 0.5%
□ Register subnet 112 trên Finney
□ git push origin main + submit production → adopted
□ Monitor champion + sync upstream định kỳ
```

---

## Lỗi thường gặp khi mới bắt đầu

| Triệu chứng | Nguyên nhân | Cách fix |
|-------------|-------------|----------|
| `Cannot submit: no open solver round` | Round chưa mở | `curl $VALIDATOR_URL/v1/solver/round`, đợi round mới |
| Screening stage 2 fail | Docker build lỗi / thiếu dep | Build với `--network=none`; dep phải có trong solver-base hoặc vendor wheel |
| Điểm luôn 0 | Exception hoặc plan invalid | Chạy scoring_lab, đọc error từng scenario |
| HTTP 401 submit | Hotkey/signature sai | Kiểm tra wallet path, hotkey name, đã register chưa |
| Local OK, production thua | Shadow cases ẩn | Không overfit benchmark public; test nhiều scenario hơn |

---

## Lộ trình thời gian gợi ý

| Tuần | Việc làm |
|------|----------|
| **Tuần 1** | Setup môi trường, fork solver, submit local lần đầu, hiểu scoring |
| **Tuần 2** | scoring_lab bench, fix điểm 0, hiểu baseline routing |
| **Tuần 3** | Cải thiện cross-DEX / split routing, đạt điểm > champion local |
| **Tuần 4** | Register mainnet, submit production, monitor |

---

## Bắt đầu ngay

Nếu bạn đã clone cả hai repo:

```bash
# Terminal 1 — testnet (tuỳ chọn, cho submit local)
cd ~/minotaur_subnet && source .venv/bin/activate
make testnet-up

# Terminal 2 — solver dev + test
export MINOTAUR_SOLVER_REPO=~/minotaur-solver
cd ~/minotaur_subnet && source .venv/bin/activate
./scripts/local_miner_step1.sh
```

Trong khi testnet khởi động, sửa `~/minotaur-solver/solver.py` theo **Giai đoạn 2**. Chi tiết fork/clone: [fork_and_update_owner_code.md](./fork_and_update_owner_code.md).
