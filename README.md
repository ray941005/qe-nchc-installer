# Quantum ESPRESSO installer for 國網創進一號

在創進一號上從原始碼建置並安裝 [Quantum ESPRESSO](https://www.quantum-espresso.org/)。
不用 container、不用 Spack、不需要 root。

```bash
git clone https://github.com/ray941005/qe-nchc-installer.git
./qe-nchc-installer/install.sh
```

可以從任何目錄、由任何使用者執行，大約 10 分鐘。

## 安裝

預設裝出來的東西：

| | |
| --- | --- |
| 版本 | Quantum ESPRESSO 7.6 |
| 位置 | `~/opt/quantum-espresso/7.6-intel-2024.0` |
| 工具鏈 | `intel/2024_01_46`（ifort + Intel MPI 2021.11 + MKL 2024.0） |
| 功能 | MPI + OpenMP + ScaLAPACK(MKL)，`-xCORE-AVX512` |
| 編譯平行度 | 16 |
| 裝完 | 跑一次 SCF 驗證，並產生 Lmod modulefile |

想先看它打算做什麼：

```bash
./qe-nchc-installer/install.sh --dry-run
```

login node 是共用的，也可以把編譯丟到 Slurm。會自動找出你的 account，送到
`development` partition，用 `sbatch --wait` 等到結束，所以還是一句指令：

```bash
./qe-nchc-installer/install.sh --slurm --jobs 56
```

## 裝完怎麼用

裝完腳本會把下面兩種用法印出來。

Lmod：

```bash
module use ~/opt/modulefiles
module load quantum-espresso/7.6-intel-2024.0
mpirun -np 8 pw.x -in scf.in
```

把 `module use` 那行放進 `~/.bashrc`，以後只要 `module load`。

或者不用 Lmod：

```bash
source ~/opt/quantum-espresso/7.6-intel-2024.0/etc/qe-env.sh
mpirun -np 8 pw.x -in scf.in
```

兩種方式都會順便載入 `intel/2024_01_46`。執行檔是動態連結 Intel MPI 和 MKL 的，
跑的時候也需要這個模組。

Slurm 作業範例在 [`examples/pw-scf.sbatch`](examples/pw-scf.sbatch)。

同一個版本加同一套工具鏈，module 名稱是固定的。如果你把同一版裝到兩個不同的
prefix，第二次安裝會把 module 改指到新位置並印出 WARN 告訴你舊的在哪。要讓兩份
同時可載入，用 `--modulefile-dir` 分開。

## 選項

```
--prefix DIR            安裝位置
--version VER           7.6（預設）/ 7.5 / 7.4.1
--compiler ifort|ifx    Fortran 編譯器（預設 ifort，理由見下）
--jobs N                編譯平行度
--arch-flags FLAGS      覆寫 CPU 最佳化旗標
--build-root DIR        原始碼與建置目錄（預設 ~/.cache/qe-installer）
--modulefile-dir DIR    modulefile 位置（預設 ~/opt/modulefiles）
--test none|smoke|full  裝完驗證到什麼程度（預設 smoke）
--slurm                 用 Slurm 作業編譯
--keep-build            保留建置目錄
--force                 即使已是最新也重建
--verbose               即時輸出編譯訊息
--dry-run               只印計畫
```

## 怎麼做到可復現

目標是同一個 commit 的這個 repo，不管誰在什麼時候跑，裝出來的東西都一樣。

所有輸入都寫死版本：

| 輸入 | 釘的方式 | 在哪 |
| --- | --- | --- |
| QE 原始碼 | git tag 加 commit SHA | `config/versions/*.sh` |
| QE 的 8 個 submodule | QE tree 自己記錄的 gitlink | 原始碼裡 |
| 編譯器 / MPI / BLAS / LAPACK / ScaLAPACK / FFT | `intel/2024_01_46` | `config/platform.sh` |
| CPU 旗標 | `-xCORE-AVX512` | `config/platform.sh` |
| 測試贗勢檔 | 隨 repo 附帶，比對 sha256 | `tests/smoke/` |
| 測試答案 | 參考能量與容差 | `tests/smoke/expected.sh` |

模組名稱一律寫完整版本號，不寫 `intel`。Lmod 的預設版本 `(D)` 會隨站方更新改變，
那是「今天能裝、下個月裝出別的東西」最常見的原因。

拿到的東西都會驗：

- clone 完比對 `git rev-parse HEAD` 和寫死的 SHA。tag 可以被上游移動，commit hash 不行。
- submodule 初始化後檢查 `git submodule status` 沒有 `+`。
- 贗勢檔比對 sha256。
- `module load` 之後檢查編譯器真的在 PATH、`MKLROOT` 和 `I_MPI_ROOT` 有值。Lmod
  載入失敗時經常還是回 0，所以不看回傳值。

另外：

- 開頭先 `module purge`，Lmod 也是腳本自己 source 起來的，不依賴使用者的 `.bashrc`。
- 先裝到 `<prefix>.stage.$$`，驗證過了才 `mv` 進 `<prefix>`。編譯失敗或中途 Ctrl-C
  不會留半成品，重裝也沒有「安裝中不能用」的空窗。
- 重跑會讀 `manifest.json` 比對 commit、工具鏈、旗標，一樣就跳過。同一個 prefix
  的併發安裝用 `flock` 排隊。
- 每次安裝寫一份 `<prefix>/share/quantum-espresso/manifest.json`，記錄 installer
  自己的 commit、QE 與所有 submodule 的 commit、編譯器 / MPI / MKL / CMake 版本、
  完整 CMake 參數、主機與 CPU、`pw.x` 的 sha256。
- 最後跑一個 bulk silicon SCF（2 rank，幾秒），把總能量和參考值比對。這會抓到連結
  得起來但算錯的建置，例如 BLAS 接錯、FFT 壞掉、最佳化旗標開太兇。參考值在寫進
  repo 前確認過 1/2/4 rank 與 1/4 thread 下都位元相同。`--test full` 會再跑上游的
  `ctest -L pw`。

## 幾個選擇

**用 git clone 不用 release tarball。** GitLab 自動產生的 archive 裡 `external/`
底下的 submodule 全是空目錄，拿來 build 會缺東西。而且那種 archive 是即時壓縮的，
sha256 不保證長期不變。git tag 加 commit SHA 永遠可驗證，submodule 版本也由 QE
自己記錄，不用另外維護一份 hash 清單。shallow clone 實測約 7 秒，submodule 約 50 秒。

**預設 ifort 不用 ifx。** oneAPI 2024.0 的 ifx 2024.0.2 編 QE 7.6 時，在
`PHonon/PH/symdynph_gq.f90` 觸發 internal compiler error（segfault）。同樣的原始碼
和參數換 ifort 就編得過。`--compiler ifx` 還留著，等站方升級 oneAPI 之後切換只要
一個旗標。

**整套數值函式庫都用 MKL。** `-DBLA_VENDOR=Intel10_64lp` 讓 CMake 一次把 BLAS、
LAPACK、ScaLAPACK、BLACS、FFTW3 介面都指到 MKL，不用自己建 OpenBLAS 或
netlib-ScaLAPACK，版本也不會混。站上的 `libs/scalapack/2.2.0-intel-oneapi-2023.2`
是用 oneAPI 2023.2 建的，跟 2024.0 混用沒必要。

**`-xCORE-AVX512` 寫死。** login node 和 x86 計算節點（`icpnp*`、`icpnq*`）都是
Xeon Platinum 8480+，AVX-512 一致可用。假設寫在 `config/platform.sh`，可用
`--arch-flags` 覆寫。

## 實測

在 `ilgn02` 上跑的結果：

| | login node (`-j32`) | Slurm `development` (`-j32`) |
| --- | --- | --- |
| 總時間 | 7 分 38 秒 | 3 分 34 秒（含排隊） |
| 其中編譯 | 6 分 24 秒 | 2 分 34 秒 |
| 執行檔數量 | 107 | 107 |
| 安裝樹大小 | 1.2 GiB | 1.2 GiB |
| SCF 驗證 | 與參考值位元相同 | 與參考值位元相同 |

Slurm 那次是 job 1085605，跑在 `icpnp322`。在 allocation 裡驗證會自動改用 `srun`。
重跑已裝好的版本（沒帶 `--force`）會直接跳過。

## Repo 結構

```
install.sh                     進入點：參數解析與流程
config/
  platform.sh                  站台相關的東西只放這裡
  versions/{7.6,7.5,7.4.1}.sh  各版本的 git tag 與 commit SHA
lib/
  common.sh                    log、錯誤 trap、checksum、flock
  preflight.sh                 動手前的檢查
  toolchain.sh                 Lmod bootstrap 與工具鏈驗證
  source.sh                    取原始碼並驗證
  build.sh                     CMake configure / compile / 原子式安裝
  postinstall.sh               env script、modulefile、manifest
  selftest.sh                  SCF 驗證與 ctest
share/                         產生 env script、modulefile、sbatch 的範本
tests/smoke/                   bulk silicon SCF、贗勢檔、參考能量
examples/pw-scf.sbatch         生產環境作業範例
```

要搬到別的叢集，改 `config/platform.sh` 就好：Lmod init 路徑、平台 fingerprint、
模組名稱、編譯器 wrapper、CPU 旗標、Slurm 預設值。`lib/` 底下沒有站台假設。如果
目標機器沒有 Intel 工具鏈，還要在 `lib/build.sh` 換掉 `BLA_VENDOR` 並改用
`mpicc` / `mpif90`。

## 疑難排解

**`this installer targets NCHC Forerunner 1 ...`**
你不在創進一號上。

**`cannot reach https://gitlab.com/QEF/q-e.git`**
login node 需要對外 HTTPS。如果被擋，先在別處
`git clone --recurse-submodules` 好放到 `<build-root>/src/q-e-7.6`，腳本會偵測並
重用，commit 一樣會驗。

**`not enough free space`**
建置要約 8 GiB，安裝樹 1.2 GiB。可以 `--build-root /work1/$USER/qe-build`。

**編譯失敗**
log 在 `~/.cache/qe-installer/logs/<version>-<toolchain>-<compiler>/`，
或用 `--verbose` 即時看。

**想知道某個安裝是怎麼來的**

```bash
cat ~/opt/quantum-espresso/7.6-intel-2024.0/share/quantum-espresso/manifest.json
```

## 限制

- 只在創進一號驗證過，preflight 會擋掉其他機器。
- 需要 login node 對外 HTTPS。
- 只建核心套件（PW、CP、PP、PHonon、NEB、TDDFPT、EPW 等 107 個執行檔），沒開
  HDF5 和 GPU。
- `--compiler ifx` 在目前的 oneAPI 2024.0 會失敗。
