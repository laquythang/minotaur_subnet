# Fork repo solver & đồng bộ code từ owner

Hướng dẫn chi tiết: fork `subnet112/minotaur-solver` sang GitHub của bạn, và cập nhật khi owner thay đổi code gốc.

**Repo gốc (upstream):** https://github.com/subnet112/minotaur-solver  
**Repo dev local:** `minotaur_subnet` (SDK, testnet) — xem cuối file nếu owner update repo đó.

Quay lại lộ trình miner: [dev_miner.md](./dev_miner.md)

---

## Mục lục

1. [Tại sao cần fork?](#1-tại-sao-cần-fork)
2. [Hai repo, hai thư mục độc lập trên máy](#2-hai-repo-hai-thư-mục-độc-lập-trên-máy)
3. [Fork trên GitHub (lần đầu)](#3-fork-trên-github-lần-đầu)
4. [Clone fork về máy (ngoài `minotaur_subnet`)](#4-clone-fork-về-máy-ngoài-minotaur_subnet)
5. [Thiết lập remote `upstream` (một lần)](#5-thiết-lập-remote-upstream-một-lần)
6. [Chạy miner test với solver ngoài project](#6-chạy-miner-test-với-solver-ngoài-project)
7. [Khi owner update code — quy trình sync](#7-khi-owner-update-code--quy-trình-sync)
8. [Resolve conflict](#8-resolve-conflict)
9. [Test sau khi sync](#9-test-sau-khi-sync)
10. [Khi nào nên sync?](#10-khi-nào-nên-sync)
11. [Sync an toàn trên nhánh riêng](#11-sync-an-toàn-trên-nhánh-riêng)
12. [Trường hợp đặc biệt](#12-trường-hợp-đặc-biệt)
13. [Update repo `minotaur_subnet`](#13-update-repo-minotaur_subnet)
14. [Lỗi thường gặp](#14-lỗi-thường-gặp)
15. [Tóm tắt nhanh](#15-tóm-tắt-nhanh)

---

## 1. Tại sao cần fork?

Validator **không** nhận file solver trực tiếp từ máy bạn (production). Họ **clone repo GitHub** → build Docker → benchmark.

| Cách | Vấn đề |
|------|--------|
| Clone `subnet112/minotaur-solver` rồi sửa local | Không push được lên repo gốc (không có quyền) |
| **Fork** → `your-user/minotaur-solver` | Repo **của bạn** → push commit → submit URL repo của bạn |

Submit production cần URL dạng:

```
https://github.com/<your-user>/minotaur-solver
```

---

## 2. Hai repo, hai thư mục độc lập trên máy

Owner thiết kế **hai repository Git riêng**. Trên máy bạn sẽ có **hai folder cùng cấp** (ví dụ trong `$HOME`):

```
~/minotaur_subnet/              ← SDK, scoring lab, local testnet, scripts/
    minotaur_subnet/              ← package Python (harness, miner CLI)
    platform/local_testnet/       ← make testnet-up, .env RPC
    scripts/local_miner_step*.sh  ← chạy test, trỏ sang repo solver

~/minotaur-solver/              ← code miner SUBMIT (fork GitHub của bạn)
    solver.py                     ← SOLVER_CLASS — file bạn sửa chính
    Dockerfile
    strategies/dex_aggregator/
```

| Repo GitHub | Thư mục local | Vai trò |
|-------------|---------------|---------|
| `<you>/minotaur_subnet` | `~/minotaur_subnet` | Dev/test — **không** submit solver từ đây |
| `<you>/minotaur-solver` | `~/minotaur-solver` | Code miner — **validator clone repo này** |

**Quan trọng:**

- `minotaur-solver` **nằm ngoài** project `minotaur_subnet` — không copy solver vào trong subnet trừ khi bạn cố ý dùng workaround.
- Scripts test chạy **từ** `minotaur_subnet`, đọc solver qua biến `MINOTAUR_SOLVER_REPO`.
- Update một repo **không** tự cập nhật repo kia.

| Repo | Ai sở hữu | Khi owner update |
|------|-----------|------------------|
| `minotaur-solver` | Fork của bạn | `git fetch upstream && merge` — **quan trọng nhất** |
| `minotaur_subnet` | Fork/clone của bạn | `git pull` trên nhánh dev |

Skeleton `minotaur_subnet/docker/example-solver/` **không** thay thế `minotaur-solver`.

---

## 3. Fork trên GitHub (lần đầu)

### Bước 1 — Mở repo gốc

Trình duyệt: https://github.com/subnet112/minotaur-solver

### Bước 2 — Fork

1. Đăng nhập GitHub
2. Nút **Fork** (góc phải trên)
3. Chọn tài khoản / organization của bạn
4. Giữ tên `minotaur-solver` (khuyến nghị — dễ theo doc)

### Bước 3 — Xác nhận

Sau fork bạn có URL:

```
https://github.com/<your-user>/minotaur-solver
```

**Checkpoint:**

- [ ] Repo fork hiện trên GitHub account của bạn
- [ ] Repo **public** (validator cần clone được)

---

## 4. Clone fork về máy (ngoài `minotaur_subnet`)

**Khuyến nghị:** Fork trên GitHub trước → clone **từ fork của bạn** (để `origin` = repo push/submit được).

Thay `<your-user>` bằng username GitHub (ví dụ `laquythang`):

```bash
# Solver — repo RIÊNG, cùng cấp với minotaur_subnet
git clone https://github.com/<your-user>/minotaur-solver.git ~/minotaur-solver
cd ~/minotaur-solver

# Subnet — nếu chưa có
git clone https://github.com/<your-user>/minotaur_subnet.git ~/minotaur_subnet
cd ~/minotaur_subnet
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

Ví dụ đầy đủ:

```bash
git clone https://github.com/laquythang/minotaur-solver.git ~/minotaur-solver
git clone https://github.com/laquythang/minotaur_subnet.git ~/minotaur_subnet
```

### Kiểm tra cấu trúc solver

```bash
ls ~/minotaur-solver
```

Kỳ vọng thấy:

| File / thư mục | Vai trò |
|----------------|---------|
| `solver.py` | Entry point; cuối file có `SOLVER_CLASS = ...` |
| `Dockerfile` | `FROM ghcr.io/subnet112/solver-base:v1` |
| `README.md` | Bắt buộc khi screening |
| `strategies/dex_aggregator/baseline_solver.py` | Engine baseline |
| `common/` | Helper (ABI, parsing) |

### Kiểm tra remote

```bash
cd ~/minotaur-solver
git remote -v
```

Kỳ vọng `origin` trỏ về repo **của bạn**:

```
origin  https://github.com/<your-user>/minotaur-solver.git (fetch)
origin  https://github.com/<your-user>/minotaur-solver.git (push)
```

**Checkpoint:**

- [ ] `~/minotaur-solver` và `~/minotaur_subnet` là **hai folder khác nhau**
- [ ] Có đủ `solver.py`, `Dockerfile`, `strategies/`, `README.md`
- [ ] `origin` là repo fork của bạn

---

## 5. Thiết lập remote `upstream` (một lần)

Để sau này lấy code mới từ owner:

```bash
cd ~/minotaur-solver

git remote add upstream https://github.com/subnet112/minotaur-solver.git

git remote -v
```

Kỳ vọng:

```
origin    https://github.com/<your-user>/minotaur-solver.git (fetch/push)
upstream  https://github.com/subnet112/minotaur-solver.git    (fetch)
```

Nếu đã thêm nhầm hoặc URL sai:

```bash
git remote remove upstream
git remote add upstream https://github.com/subnet112/minotaur-solver.git
```

**Checkpoint:**

- [ ] `git remote -v` hiển thị cả `origin` và `upstream`

---

## 6. Chạy miner test với solver ngoài project

Sau khi clone `~/minotaur-solver`, cấu hình path và chạy test **từ** `~/minotaur_subnet`.

### 6.1 — Biến môi trường (bắt buộc)

```bash
export MINOTAUR_SOLVER_REPO=~/minotaur-solver
export PATH="$HOME/.foundry/bin:$PATH"   # anvil — cho scoring_lab bench
```

Thêm vào `~/.bashrc` nếu muốn giữ cố định:

```bash
echo 'export MINOTAUR_SOLVER_REPO=~/minotaur-solver' >> ~/.bashrc
```

Scripts `local_miner_common.sh` mặc định tìm `~/minotaur-solver` nếu biến chưa set.

### 6.2 — RPC Base (cho bench)

```bash
cd ~/minotaur_subnet/platform/local_testnet
cp .env.example .env
# Sửa BASE_ALCHEMY_RPC_URL=... (Alchemy free tier)
```

Scripts tự load file `.env` này.

### 6.3 — Pipeline test từng bước

```bash
cd ~/minotaur_subnet
source .venv/bin/activate
chmod +x scripts/local_miner_*.sh

./scripts/local_miner_step1.sh   # screening stage 1 + docker build + bench smoke
./scripts/local_miner_step2.sh   # zero-score guard
./scripts/local_miner_step3.sh   # routing
./scripts/local_miner_step4.sh   # cross-DEX
./scripts/local_miner_step5.sh   # split routing
./scripts/local_miner_step6.sh   # bench + submit local testnet (optional)

# Hoặc một lần:
./scripts/local_miner_run_all.sh
```

Mỗi script in dòng `solver repo: /home/.../minotaur-solver` — xác nhận path đúng.

### 6.4 — Cấu hình GitHub submit

Sửa `scripts/miner_github.env` (username của bạn):

```bash
export MINOTAUR_SUBNET_REPO_URL=https://github.com/<your-user>/minotaur_subnet
export MINER_GITHUB_REPO_URL=https://github.com/<your-user>/minotaur-solver
```

Submit local / mainnet dùng **URL fork solver**, commit từ `~/minotaur-solver`:

```bash
cd ~/minotaur-solver
git push origin main

cd ~/minotaur_subnet && source .venv/bin/activate
source scripts/miner_github.env

python -m minotaur_subnet.miner.main submit \
  --repo-url "$MINER_GITHUB_REPO_URL" \
  --commit-hash $(git -C ~/minotaur-solver rev-parse HEAD) \
  --hotkey default \
  --validator-url http://localhost:8080 \
  --poll
```

> **Không cần** `publish_miner_solver.sh` khi dùng repo `minotaur-solver` riêng — script đó chỉ dành cho layout solver nhúng trong `minotaur_subnet/miner_solver/`.

### 6.5 — Sync code owner vào clone local

Nếu chưa fork mà clone thẳng upstream, hoặc cần refresh baseline:

```bash
cd ~/minotaur_subnet
./scripts/sync_minotaur_solver_upstream.sh
# → cập nhật ~/minotaur-solver từ subnet112/minotaur-solver
```

**Checkpoint test local:**

- [ ] `./scripts/local_miner_step1.sh` → screening PASSED + Docker OK
- [ ] `solver repo:` trỏ `~/minotaur-solver`, không phải path trong `minotaur_subnet`
- [ ] (Tuỳ chọn) `make testnet-up` + submit → `scored`

---

## 7. Khi owner update code — quy trình sync

### Bước A — Lưu công việc đang làm

```bash
cd ~/minotaur-solver
git status

# Cách 1: commit WIP
git add .
git commit -m "WIP: my routing improvements"

# Cách 2: stash (chưa muốn commit)
git stash push -m "before upstream sync"
```

### Bước B — Lấy code mới từ owner

```bash
git fetch upstream
```

### Bước C — Xem owner đổi gì

```bash
# Commit mới từ owner (chưa merge)
git log HEAD..upstream/main --oneline

# File nào thay đổi
git diff HEAD..upstream/main --stat
```

File thường đổi khi owner update:

- `strategies/dex_aggregator/baseline_solver.py` — baseline champion
- `common/`, `strategies/dex_aggregator/*` — routing math, codec
- `Dockerfile`, `requirements.txt` — build
- `solver.py` — entry point

### Bước D — Merge vào nhánh của bạn

```bash
git checkout main          # hoặc nhánh dev của bạn
git merge upstream/main
```

Nếu có conflict → xem [mục 8](#8-resolve-conflict).

Sau khi resolve xong:

```bash
git add .
git commit -m "Merge upstream: sync baseline from subnet112"
git push origin main
```

Nếu trước đó dùng `git stash`:

```bash
git stash pop
# resolve conflict nếu có giữa stash và code mới
```

### Bước E — Test lại

Xem [mục 9](#9-test-sau-khi-sync). **Không submit production** ngay sau merge upstream.

---

## 8. Resolve conflict

Git báo conflict khi **cùng một dòng** bạn và owner đều sửa.

### Nguyên tắc

| File | Giữ gì |
|------|--------|
| `baseline_solver.py`, `pool_math.py`, `v3_codec.py`, … (engine gốc) | Ưu tiên **upstream**, trừ khi bạn cố ý fork toàn bộ engine |
| `solver.py` (class custom của bạn) | Giữ **code của bạn** |
| `strategies/<app_custom>/` | Giữ **code của bạn** |
| `Dockerfile` | Thường lấy upstream, rồi thêm phần custom nếu có |

### Sửa conflict thủ công

File conflict có marker:

```
<<<<<<< HEAD
code của bạn
=======
code từ upstream
>>>>>>> upstream/main
```

Xóa marker, giữ phần đúng, rồi:

```bash
git add <file-đã-sửa>
git commit -m "Resolve merge conflict with upstream"
```

### Khuyến nghị kiến trúc (tránh conflict lâu dài)

**Không** sửa trực tiếp `baseline_solver.py` lâu dài. Thay vào đó:

```python
# solver.py
from strategies.dex_aggregator.baseline_solver import BaselineSwapSolver

class MySwapSolver(BaselineSwapSolver):
    def generate_plan(self, intent, state, snapshot=None):
        # custom logic ở đây hoặc trong strategies/my_app/
        return super().generate_plan(intent, state, snapshot)

SOLVER_CLASS = MySwapSolver
```

Khi upstream update baseline, merge dễ hơn; logic custom tách riêng.

---

## 9. Test sau khi sync

Owner đổi baseline có thể làm điểm của bạn **tăng** (inherit cải tiến) hoặc **giảm** (conflict resolve sai).

### 1. Docker build

```bash
export MINOTAUR_SOLVER_REPO=~/minotaur-solver
cd ~/minotaur-solver
docker build --network=none --memory=4g -t my-solver:local .
```

### 2. Import smoke test (hoặc `./scripts/local_miner_step1.sh`)

```bash
docker run --rm --network=none --read-only \
  --tmpfs=/tmp:size=64m --memory=2g --cpus=1.0 \
  --entrypoint python my-solver:local \
  -c "from solver import SOLVER_CLASS; s=SOLVER_CLASS(); s.initialize({'chain_ids':[8453]}); print(s.metadata())"
```

### 3. Scoring lab (từ `minotaur_subnet`)

```bash
export MINOTAUR_SOLVER_REPO=~/minotaur-solver
cd ~/minotaur_subnet
source .venv/bin/activate

# RPC trong platform/local_testnet/.env hoặc export:
export BASE_ALCHEMY_RPC_URL=https://base-mainnet.g.alchemy.com/v2/YOUR_KEY
export PATH="$HOME/.foundry/bin:$PATH"

./scripts/local_miner_step2.sh   # bench --limit 10
# hoặc:
python -m minotaur_subnet.harness.scoring_lab bench \
  --base-rpc $BASE_ALCHEMY_RPC_URL \
  --candidate ~/minotaur-solver/solver.py \
  --limit 10
```

### 4. Submit local testnet (nếu điểm ổn)

```bash
export MINOTAUR_SOLVER_REPO=~/minotaur-solver
export VALIDATOR_URL=http://localhost:8080
export MINER_GITHUB_REPO_URL=https://github.com/<your-user>/minotaur-solver

cd ~/minotaur-solver && git push origin main
cd ~/minotaur_subnet && source .venv/bin/activate

python -m minotaur_subnet.miner.main submit \
  --repo-url "$MINER_GITHUB_REPO_URL" \
  --commit-hash $(git -C ~/minotaur-solver rev-parse HEAD) \
  --hotkey default \
  --validator-url $VALIDATOR_URL \
  --poll
```

**Checkpoint sau sync:**

- [ ] Docker build OK
- [ ] Scoring lab không regression (điểm ≥ trước merge, hoặc vẫn > champion + 0.5%)
- [ ] Local submit → `scored` (nếu testnet đang chạy)

---

## 10. Khi nào nên sync?

| Tình huống | Hành động |
|------------|-----------|
| Owner release / commit lớn trên `minotaur-solver` | Sync sớm |
| Champion trên network đổi (baseline mới) | Sync + benchmark lại |
| Trước khi submit mainnet | Sync + test local |
| Đang giữa thay đổi lớn chưa xong | Hoãn sync, hoặc sync trên nhánh riêng |
| Chỉ sửa strategy nhỏ, upstream im lặng | Không bắt buộc mỗi ngày |

Theo dõi repo gốc:

- Watch repo trên GitHub: **Watch → Custom → Releases**
- Hoặc định kỳ: `git fetch upstream && git log HEAD..upstream/main --oneline`

---

## 11. Sync an toàn trên nhánh riêng

Không muốn phá `main` đang chạy ổn:

```bash
cd ~/minotaur-solver
git fetch upstream

git checkout -b sync-upstream-$(date +%Y-%m-%d)
git merge upstream/main

# resolve conflict, chạy test (mục 9)...

# Nếu OK, gộp vào main:
git checkout main
git merge sync-upstream-$(date +%Y-%m-%d)
git push origin main
```

---

## 12. Trường hợp đặc biệt

### Owner đổi `solver-base` Docker image

Kiểm tra `Dockerfile` upstream có đổi dòng `FROM` không:

```bash
git diff HEAD..upstream/main -- Dockerfile
```

Nếu `FROM ghcr.io/subnet112/solver-base:v1` → `v2` (ví dụ): build lại Docker, chạy screening.

### Clone nhầm repo gốc thay vì fork

Bạn vẫn dev được nhưng không push lên `subnet112/`. Sửa bằng cách đổi `origin`:

```bash
git remote rename origin upstream-temp
git remote add origin https://github.com/<your-user>/minotaur-solver.git
git push -u origin main
```

### Repo private

Production validator thường cần repo **public** để clone. Nếu private, hỏi operator về credential clone (`SUBMISSION_GIT_CLONE_*` trên API — chỉ áp dụng môi trường đặc biệt).

### Baseline mạnh hơn sau sync

Điểm có thể tăng nếu bạn inherit cải tiến. Nếu custom code bị ghi đè nhầm khi resolve conflict → điểm giảm. Luôn chạy scoring_lab so sánh trước/sau merge.

---

## 13. Update repo `minotaur_subnet`

Khi owner update SDK, screening, hoặc scoring trong repo chính:

```bash
cd ~/minotaur_subnet
git pull origin develop   # hoặc main — nhánh bạn đang dùng

source .venv/bin/activate
pip install -r requirements.txt   # nếu requirements đổi
```

Sau đó chạy lại `./scripts/local_miner_step1.sh` — pipeline có thể thay đổi.

**Không** tự động cập nhật `minotaur-solver` — phải sync `upstream` riêng ([mục 7](#7-khi-owner-update-code--quy-trình-sync)).

---

## 14. Lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách fix |
|-------------|-------------|----------|
| `solver repo not found` | Chưa clone hoặc sai path | `git clone ... ~/minotaur-solver` + `export MINOTAUR_SOLVER_REPO=~/minotaur-solver` |
| Script trỏ `miner_solver/` trong subnet | Không có `~/minotaur-solver` | Export `MINOTAUR_SOLVER_REPO` hoặc clone đúng path |
| `remote upstream already exists` | Đã add upstream trước đó | `git remote -v` kiểm tra; dùng `git fetch upstream` |
| `fatal: refusing to merge unrelated histories` | Repo fork tạo rỗng | Fork lại từ repo gốc |
| Push bị reject | Chưa pull/merge trước | `git pull origin main` rồi push lại |
| Điểm benchmark sụt sau merge | Resolve conflict sai | Test từng file conflict; chạy `./scripts/local_miner_step2.sh` |
| `git fetch upstream` lỗi 404 | URL upstream sai | `git remote set-url upstream https://github.com/subnet112/minotaur-solver.git` |

---

## 15. Tóm tắt nhanh

### Lần đầu

```
GitHub: Fork subnet112/minotaur-solver → <you>/minotaur-solver

Máy:
  git clone https://github.com/<you>/minotaur-solver.git ~/minotaur-solver
  git clone https://github.com/<you>/minotaur_subnet.git ~/minotaur_subnet
  cd ~/minotaur-solver
  git remote add upstream https://github.com/subnet112/minotaur-solver.git

  export MINOTAUR_SOLVER_REPO=~/minotaur-solver
  cd ~/minotaur_subnet && source .venv/bin/activate && pip install -r requirements.txt
  ./scripts/local_miner_step1.sh
```

### Mỗi khi owner update

```
cd ~/minotaur-solver
git fetch upstream
git log HEAD..upstream/main --oneline
git merge upstream/main
export MINOTAUR_SOLVER_REPO=~/minotaur-solver
cd ~/minotaur_subnet && ./scripts/local_miner_step1.sh
git push origin main
submit lại nếu điểm vẫn > champion + 0.5%
```

---

Quay lại: [dev_miner.md — Giai đoạn 2.1](./dev_miner.md#giai-đoạn-2-tạo-repo-solver-của-bạn-12-giờ)
