# ADR 0010：项目以 MIT 许可证开源，第三方许可限定为宽松许可

**状态**：已采纳

## 背景
00 的 OPEN-001 要求在 M0 开始前确定项目的开源许可证。它决定了能否把第三方源码 vendoring 进仓库（ADR 0002 的 NanoVG 及其自带的 fontstash、stb_truetype，ADR 0004 的 GLFW，02 的 stb_image），也决定了 05 的 `fontstash` 后端所需的测试字体能否入库。这些上游都是宽松许可（zlib、MIT 或公有领域），与常见的开源许可证都兼容，真正待定的是本项目自身的许可证。

## 决策
- 本项目以 **MIT 许可证**发布。仓库根目录放 `LICENSE`，内容为 MIT 标准文本，版权行为 `Copyright (c) 2026 orangepro2001`。项目自有源文件不加逐文件许可头。
- 当前不要求贡献者签署 CLA 或 DCO；如需引入，另立 ADR。
- 允许入库的第三方许可证（SPDX 标识）：`MIT`、`BSD-2-Clause`、`BSD-3-Clause`、`ISC`、`Zlib`、`Unlicense`、`CC0-1.0`。多许可的库只要其中一项在清单内即可（如 stb 的 `MIT OR Unlicense`）。`OFL-1.1` 只允许用于 `tests/fonts/` 下的测试字体，这些字体不编译进库，也不随发布产物分发。
- 禁止入库：著佐权许可（GPL、LGPL、AGPL、MPL、EPL 等）、带非商用或用途限制的许可，以及没有明确许可证的代码、字体和图像。扩大允许清单须新增 ADR（可与 REQ-CONV-029 要求的新增依赖 ADR 合为一份）。
- 许可义务的落实方式见 15 的 REQ-CONV-030 至 REQ-CONV-032：
  - 上游许可文本原样保留在各 `third_party/<库>/`；
  - 根目录 `THIRD_PARTY_NOTICES.md` 逐项登记第三方库与测试字体；
  - zlib 许可要求修改版"明确标注"，由 `PATCHES.md` 登记（REQ-CONV-017）加被修改文件的文件头注释共同满足。
- 测试字体 `NanoTestSans`（05 的 REQ-TEXT-037）取自 `OFL-1.1` 字体的子集，改名为 `NanoTestSans`。来源字体如声明了保留字体名（Reserved Font Name），新名不得包含该保留名。

## 后果
- 使用者可以把本框架用于闭源和商业产品，只需保留本项目的版权与许可声明。当前上游的许可（zlib；stb 可选公有领域）对二进制分发没有额外的声明义务。`THIRD_PARTY_NOTICES.md` 仍提供汇总，方便应用随产品附带。
- MIT 不含明示的专利授权；本项目接受这一点，以换取最简短、最易被接受的条款。
- 只允许宽松许可，著佐权的库无法直接采用，需要时另找替代或自行实现。
- OPEN-001 关闭；14 中 M0 的源码 vendoring 不再受阻。

## 被否方案
- **zlib**：与 NanoVG、GLFW 一致，义务同样宽松；但使用者对 MIT 更熟悉，Zig 生态中也更常见。
- **Apache-2.0，或 MIT OR Apache-2.0 双许可**：有明示专利授权，但条款长，对修改文件有标注要求和 NOTICE 文件要求，对个人项目收益不足。
- **LGPL / GPL**：Zig 项目通常静态链接，LGPL 对静态链接的再链接义务会让大量使用者回避。
