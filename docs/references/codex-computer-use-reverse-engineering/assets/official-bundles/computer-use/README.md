# Official Computer Use Bundles

这个目录保存从本地 bundled plugin cache 归档的官方 `computer-use` zip 包，用作逆向分析和版本对比输入。

## 当前归档

| File | Size | SHA-256 |
| --- | ---: | --- |
| `1.0.750.zip` | 13 MB | `7afe231e98ddb3b95030c8c56bb178a0217e98fcbb08abf9e1b467fd7ead5b9d` |
| `1.0.755.zip` | 13 MB | `cfabe3f41bfec1ea1d5f99ca2f5424eac98487e9474a099394c372d5df7a6460` |

## 维护约定

- 这里的 zip 只作为原始官方制品归档，不直接参与构建。
- 新增 zip 时同步更新 `SHA256SUMS` 和本文件。
- 该目录下的 zip 通过 Git LFS 跟踪，避免把大二进制直接写入普通 Git object。
