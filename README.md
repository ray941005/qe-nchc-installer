# Quantum ESPRESSO installer for NCHC Forerunner 1 (國網創進一號)

一鍵、可復現地在**國網中心創進一號**上，從原始碼建置並安裝
[Quantum ESPRESSO](https://www.quantum-espresso.org/)。
不使用 container，不使用 Spack，不需要 root 權限。

```bash
git clone https://github.com/ray941005/qe-nchc-installer.git
./qe-nchc-installer/install.sh
```

就這樣。腳本可以從**任何目錄**、由**任何使用者**執行，全程約 10–15 分鐘。

---

## 目錄

- [安裝](#安裝)
- [安裝完成後怎麼用](#安裝完成後怎麼用)
- [命令列選項](#命令列選項)
- [可復現性是怎麼做到的](#可復現性是怎麼做到的)
- [設計決策與理由](#設計決策與理由)
- [Repo 結構](#repo-結構)
- [實測紀錄](#實測紀錄)
- [疑難排解](#疑難排解)
- [移植到其他叢集](#移植到其他叢集)
- [已知限制](#已知限制)

---

## 安裝

### 最短路徑

```bash
git clone https://github.com/ray941005/qe-nchc-installer.git
./qe-nchc-installer/install.sh
```

預設行為：

| 項目 | 預設值 |
| --- | --- |
| 版本 | Quantum ESPRESSO 7.6 |
| 安裝位置 | `~/opt/quantum-espresso/7.6-intel-2024.0` |
| 工具鏈 | `intel/2024_01_46`（oneAPI 2024.0：ifort + Intel MPI 2021.11 + MKL 2024.0） |
| 功能 | MPI + OpenMP + ScaLAPACK(MKL)，`-xCORE-AVX512` |
| 編譯平行度 | 16（login node 上的禮貌預設值） |
| 安裝後 | 自動跑 smoke test，並產生 Lmod modulefile |

### 先看它要做什麼再決定

```bash
./qe-nchc-installer/install.sh --dry-run
```

### 在計算節點上編譯（可選）

login node 是共用資源。要把編譯丟到 Slurm：

```bash
./qe-nchc-installer/install.sh --slurm --jobs 56
```

會自動偵測你的 Slurm account，送到 `development` partition，並用
`sbatch --wait` 等到結束——對使用者而言仍然是「一句指令」。

---

## 安裝完成後怎麼用

安裝腳本結束時會把下面兩種用法印出來。

**方式一：Lmod（建議）**

```bash
module use ~/opt/modulefiles
module load quantum-espresso/7.6-intel-2024.0

mpirun -np 8 pw.x -in scf.in
```

把 `module use` 那行放進 `~/.bashrc`，之後就只要 `module load`。

**方式二：純 shell**

```bash
source ~/opt/quantum-espresso/7.6-intel-2024.0/etc/qe-env.sh
mpirun -np 8 pw.x -in scf.in
```

兩種方式都會自動載入 `intel/2024_01_46`——QE 的執行檔動態連結 Intel MPI 與
MKL，**執行時期**同樣需要這個模組，不是只有編譯時要。

實際的 Slurm 作業範例見 [`examples/pw-scf.sbatch`](examples/pw-scf.sbatch)。

> 同一個版本＋工具鏈組合，對應的 module 名稱是固定的
> （`quantum-espresso/7.6-intel-2024.0`）。如果你把同一個版本裝到兩個不同的
> prefix，第二次安裝會把這個 module 改指到新的位置，並印出明確的 WARN 說明
> 舊位置與新位置。要讓兩份安裝同時可載入，請用 `--modulefile-dir` 分開。

---

## 命令列選項

```
--prefix DIR          安裝位置
--version VER         QE 版本：7.6（預設）/ 7.5 / 7.4.1
--compiler ifort|ifx  Fortran 編譯器（預設 ifort，理由見下）
--jobs N              編譯平行度
--arch-flags FLAGS    覆寫 CPU 最佳化旗標
--build-root DIR      原始碼與建置目錄（預設 ~/.cache/qe-installer）
--modulefile-dir DIR  modulefile 產生位置（預設 ~/opt/modulefiles）
--test none|smoke|full  安裝後驗證的程度（預設 smoke）
--slurm               改用 Slurm 作業編譯
--keep-build          保留建置目錄
--force               即使已是最新也重建
--verbose             即時輸出編譯訊息
--dry-run             只印計畫不執行
```

---

## 可復現性是怎麼做到的

「可復現」的定義是：**同一個 commit 的這個 repo，在這台機器上，任何時間、任何
使用者執行，都會得到位元層級上等價的安裝結果。** 具體做法：

### 1. 所有輸入都被釘住（pinned）

| 輸入 | 釘住的方式 | 位置 |
| --- | --- | --- |
| QE 原始碼 | git tag **＋ commit SHA 驗證** | `config/versions/*.sh` |
| QE 的 8 個 submodule（devxlib、fox、mbd、lapack、wannier90…） | 由已驗證的 QE tree 自己記錄的 gitlink | QE 原始碼本身 |
| 編譯器 / MPI / BLAS / LAPACK / ScaLAPACK / FFT | 單一 module **完整版本號** `intel/2024_01_46` | `config/platform.sh` |
| CPU 最佳化旗標 | 明寫 `-xCORE-AVX512` | `config/platform.sh` |
| 測試用贗勢檔 | 隨 repo 附帶 **＋ sha256 驗證** | `tests/smoke/` |
| 測試的正確答案 | 明寫參考能量與容差 | `tests/smoke/expected.sh` |

版本號一律寫死成完整版本（`intel/2024_01_46`，不是 `intel`），因為 Lmod 的預設
版本 `(D)` 會隨站方更新而改變——那正是「今天能裝、下個月裝出不一樣的東西」的
典型來源。

### 2. 取得的東西會被驗證，不是「相信」

- clone 之後比對 `git rev-parse HEAD` 與寫死的 commit SHA：**tag 可以被上游移動，
  commit hash 不行**。不符就中止。
- submodule 初始化後檢查 `git submodule status` 沒有任何 `+`（代表不在記錄的版本）。
- 贗勢檔比對 sha256。
- module 載入後，用「工具是否真的出現在 PATH」以及 `MKLROOT` / `I_MPI_ROOT`
  是否存在來驗證，而不是相信 `module load` 的回傳值（Lmod 失敗時常常仍回傳 0）。

### 3. 建置環境是乾淨的

腳本一開始就 `module purge`，不繼承使用者當下載入的任何模組；Lmod 本身也是由
腳本自己 source 起來的，不依賴使用者的 `.bashrc`。

### 4. 安裝是原子的

先安裝到 `<prefix>.stage.$$`，**smoke test 通過之後**才 `mv` 換進 `<prefix>`。
結果是：

- 編譯失敗、測試失敗、或中途被 Ctrl-C，都不會留下一個半成品讓別人的作業踩到；
- 重裝時舊版本在最後一刻才被換掉，不存在「安裝進行中 QE 不能用」的空窗。

### 5. 冪等（idempotent）

重跑 `install.sh` 時，會讀已安裝樹裡的 `manifest.json`，比對 commit、工具鏈、
編譯器與最佳化旗標；完全相同就直接跳過並印出用法。要重建才需要 `--force`。
同一個 prefix 的併發安裝用 `flock` 序列化。

### 6. 安裝結果會自我描述

每次安裝都會寫出
`<prefix>/share/quantum-espresso/manifest.json`，內容包含：

- 這個 installer repo 自己的 commit（以及當時工作目錄是否 dirty）
- QE 的 tag / commit / 全部 submodule commit
- 編譯器、MPI、MKL、CMake 的完整版本字串
- 完整的 CMake 參數列
- 主機、OS、CPU 型號
- `pw.x` 的 sha256

半年後有人問「這個 QE 到底是怎麼裝的」，答案在檔案裡，不在某個人的記憶裡。

### 7. 「能編過」不等於「是對的」

安裝最後會實際跑一個 bulk silicon 的 SCF 計算（2 個 MPI rank，數秒），並把總能量
和參考值比對：

```
OK    SCF total energy -15.84452726 Ry (reference -15.84452726 Ry, Δ=0.000e+00 Ry)
```

這個參考值在寫進 repo 之前，先確認過在 1／2／4 個 MPI rank 與 1／4 個 OpenMP
thread 下都是**位元相同**的，所以它反映的是物理，不是某個特定的平行分解方式。
這一步會抓到「連結得起來但算出垃圾」的建置——錯誤的 BLAS、壞掉的 FFT、過頭的
最佳化旗標——這類問題光看編譯有沒有過是看不出來的。

`--test full` 會額外跑上游的 `ctest -L pw` 回歸測試。

---

## 設計決策與理由

### 為什麼用 git clone 而不是 release tarball

GitLab 自動產生的 source archive **不包含 submodule**——`external/` 底下的
devxlib、fox、mbd、lapack、wannier90 等目錄全是空的，直接拿來 build 會失敗或
缺功能。而且這種 archive 是即時壓縮產生的，checksum 不保證長期穩定，拿 sha256
去釘它反而會在某天無預警爆掉。

git tag + commit SHA 是內容定址的：**永遠**可驗證，而且 submodule 的版本由已驗證
的 tree 自己記錄，不需要另外維護一份 hash 清單。
`--depth 1` 的 shallow clone 在這台機器上實測約 6 秒，submodule 約 20 秒。

### 為什麼預設是 ifort 而不是 ifx

**實測結果**：在 oneAPI 2024.0（ifx 2024.0.2）下建置 QE 7.6，在
`PHonon/PH/symdynph_gq.f90` 觸發編譯器內部錯誤：

```
error #5633: **Internal compiler error: segmentation violation signal raised**
```

同樣的原始碼、同樣的 CMake 參數，換成 ifort classic（mpiifort）可以乾淨編完
（9 分 12 秒，107 個執行檔）。所以預設是 ifort。

`--compiler ifx` 選項仍然保留：Intel 已宣告 ifort classic 終止支援，等站方升級
到較新的 oneAPI，切換只需要一個旗標，不需要改腳本。

### 為什麼整條數值堆疊都用 MKL

`-DBLA_VENDOR=Intel10_64lp` 讓 CMake 一次把 BLAS、LAPACK、ScaLAPACK、BLACS 和
FFTW3 介面全部指到 MKL。好處是：

- 不需要另外建 OpenBLAS / netlib-ScaLAPACK / FFTW，**沒有額外的相依性要維護**；
- 整包數值函式庫版本一致，不會出現 MKL 的 BLAS 配上別人的 ScaLAPACK 這種組合；
- 在 Sapphire Rapids 上 MKL 是效能最好的選擇。

站上雖然有 `libs/scalapack/2.2.0-intel-oneapi-2023.2` 模組，但那是用 oneAPI
**2023.2** 建的，和我們的 2024.0 工具鏈混用會引入不必要的 ABI 風險——MKL 內建的
ScaLAPACK 更乾淨。

### 為什麼 `-xCORE-AVX512` 可以寫死

創進一號的 login node 與 x86 計算節點（`icpnp*` / `icpnq*`）都是 Intel Xeon
Platinum 8480+（Sapphire Rapids），AVX-512 一致可用。這個假設明寫在
`config/platform.sh`，並且可用 `--arch-flags` 覆寫。

### 為什麼不用 container、不用 Spack

作業要求。不過這也不只是限制：本題的相依性其實只有「一個 Intel oneAPI 模組」，
用 CMake 直接建置反而比引入一整套 package manager 更容易讀、更容易稽核、也更容易
移植——整個站台相關的知識集中在一個 40 行的 `config/platform.sh` 裡。

### 為什麼失敗要吵

腳本全程 `set -Eeuo pipefail` 搭配 ERR trap，失敗時會印出失敗的指令、完整的呼叫
堆疊（檔案:行號）以及相關 log 的最後 20 行。所有檢查（磁碟空間、CMake 版本、
網路、可寫權限、工具鏈完整性）都在**動到任何東西之前**就做完。沒有任何一處是
「偵測到 X 不在就默默改用 Y」——那種靜默 fallback 正是可復現性的頭號殺手。

---

## Repo 結構

```
install.sh                     唯一進入點：參數解析與流程編排
config/
  platform.sh                  站台相關知識「只」放這裡（模組、旗標、Slurm 預設）
  versions/{7.6,7.5,7.4.1}.sh  每個版本的 git tag + commit SHA
lib/
  common.sh                    log、錯誤 trap、checksum、flock、abspath
  preflight.sh                 動手前的全部檢查
  toolchain.sh                 Lmod bootstrap 與工具鏈驗證
  source.sh                    取得原始碼並驗證 commit / submodule
  build.sh                     CMake configure / compile / 原子式安裝
  postinstall.sh               env script、modulefile、provenance manifest
  selftest.sh                  smoke test 與 ctest
share/
  qe-env.sh.tmpl               產生的環境設定範本
  modulefile.lua.tmpl          產生的 Lmod modulefile 範本
  build-job.sbatch.tmpl        --slurm 用的作業腳本範本
tests/smoke/
  si.scf.in                    bulk silicon SCF
  Si.pz-vbc.UPF                贗勢檔（隨 repo 附帶，避免測試時還要連外網）
  expected.sh                  參考能量、容差、贗勢 sha256
examples/
  pw-scf.sbatch                生產環境作業腳本範例
```

---

## 實測紀錄

以下是在 `ilgn02` 上的實際執行結果（可用 `install.sh --force` 重現）：

```
=== Preflight ===
[16:59:58] OK    preflight passed
[16:59:59] INFO  loading module intel/2024_01_46
[16:59:59] OK    toolchain ready (MKLROOT=/pkg/compiler/intel/2024/mkl/2024.0, ...)
=== Fetch source ===
[16:59:59] OK    source verified at 9f93ddec427d2b9a45bb72d828c6d324f62fcabd
[16:59:59] OK    submodules pinned:   (8 個，全部符合記錄的 revision)
=== Configure ===
[17:00:08] OK    configured (mpiifort -> ifort (IFORT) 2021.11.1 20231117)
=== Compile ===
[17:06:32] OK    compiled in 6m 24s
=== Install ===
[17:06:35] OK    staged 107 executables in .../7.6-intel-2024.0.stage.1266024
=== Smoke test ===
[17:06:36] OK    SCF total energy -15.84452726 Ry (reference -15.84452726 Ry, Δ=0.000e+00 Ry)
[17:06:37] OK    installed to /home/rayo5o05/opt/quantum-espresso/7.6-intel-2024.0
[17:06:37] OK    modulefile published: .../opt/modulefiles/quantum-espresso/7.6-intel-2024.0.lua
=== Done ===
```

| 量測項目 | 結果 |
| --- | --- |
| 全新安裝總時間（`-j32`，含 clone、submodule、編譯、測試） | **7 分 38 秒** |
| 其中編譯 | 6 分 24 秒 |
| shallow clone QE 原始碼 | 約 7 秒 |
| 初始化 8 個 submodule | 約 50 秒 |
| 產生的執行檔數量 | 107 |
| 安裝樹大小 | 1.2 GiB |
| smoke test 與參考值差距 | 0（位元相同） |
| 重跑（已安裝、無 `--force`） | 立即跳過，不重建 |

---

## 疑難排解

**`this installer targets NCHC Forerunner 1 ...`**
你不在創進一號上。見[移植到其他叢集](#移植到其他叢集)。

**`cannot reach https://gitlab.com/QEF/q-e.git`**
login node 需要對外 HTTPS。若站方擋掉，先在別處
`git clone --recurse-submodules` 好，放到 `--build-root <dir>/src/q-e-7.6`，
腳本會偵測並重用（commit 仍會被驗證）。

**`not enough free space`**
建置需要約 8 GiB、安裝樹約 1.2 GiB。用 `--build-root /work1/$USER/qe-build`
換到 work 檔案系統。

**編譯失敗**
完整 log 在 `~/.cache/qe-installer/logs/<version>-<toolchain>-<compiler>/`。
`--verbose` 可以即時看輸出。

**想看某個安裝是怎麼來的**

```bash
cat ~/opt/quantum-espresso/7.6-intel-2024.0/share/quantum-espresso/manifest.json
```

---

## 移植到其他叢集

照設計，只需要改 `config/platform.sh`：Lmod init 路徑、平台識別用的 fingerprint、
工具鏈模組名稱、編譯器 wrapper、CPU 旗標、Slurm 預設值。`lib/` 底下的檔案不含任何
站台相關假設。

若目標機器沒有 Intel 工具鏈，還需要在 `lib/build.sh` 換掉 `BLA_VENDOR`
（例如 OpenBLAS + netlib-ScaLAPACK），並改用 `mpicc` / `mpif90`。

---

## 已知限制

- 只在**創進一號**上驗證過。preflight 會明確擋下其他機器，而不是裝出一包沒人測過的東西。
- 建置需要 login node 對外 HTTPS（clone QE 與其 submodule）。
- 只建置預設的核心套件（PW、CP、PP、PHonon、NEB、TDDFPT、EPW…，共 107 個執行檔）。
  未啟用 HDF5（可以用站上的 `libs/hdf5/1.14.3`，但會多一個外部相依）、也未啟用 GPU。
  這些都是刻意的取捨，不是遺漏。
- `--compiler ifx` 在目前站上的 oneAPI 2024.0 會失敗（見上）。
