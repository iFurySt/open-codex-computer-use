# 配置

[English](configuration.md) | [简体中文](configuration.zh-CN.md)

配置文件默认在 `~/.config/ocu/config.json`，可以直接编辑。如果文件还不存在，可以创建一个。下面是默认配置：

```json
{
  "image": {
    "format": "png",
    "jpegQuality": 0.8,
    "maxLongEdgePixels": 1280,
    "scaleDownAfterMaxSize": true,
    "discardBelowPixelCount": 64,
    "captureTimeout": 5
  }
}
```

目前这些配置用于 macOS 截图，修改后在下一次截图时生效。也支持环境变量，优先级是 ENV > 配置文件 > 默认值。

## 命令行配置

也可以通过 `ocu config` 来配置，修改会保存到上面的文件里：

```bash
# 查看配置
ocu config

# 改成 JPG
ocu config set image.format jpg

# 查看某一项
ocu config get image.format

# 恢复默认（如果有 ENV，仍优先使用 ENV）
ocu config reset image.format

# 查看配置文件路径
ocu config path
```

`ocu` 也可以换成 `open-computer-use`。

## 配置项

| 配置项 | 默认值 | 说明 | 命令示例 |
| --- | --- | --- | --- |
| `image.format` | `png` | 输出格式，可选 `png`、`jpg`、`webp`。WebP 为无损编码。 | `ocu config set image.format webp` |
| `image.jpegQuality` | `0.8` | JPG 质量，范围 `0–1`，只影响 JPG。 | `ocu config set image.jpegQuality 0.9` |
| `image.maxLongEdgePixels` | `1280` | 图片长边上限，单位像素，范围 `1–16384`，整数。设为 `null` 关闭限制。 | `ocu config set image.maxLongEdgePixels 1920` |
| `image.scaleDownAfterMaxSize` | `true` | 超过长边上限时，`true` 等比例缩小，`false` 丢弃截图。 | `ocu config set image.scaleDownAfterMaxSize false` |
| `image.discardBelowPixelCount` | `64` | 宽 × 高小于此值时丢弃，等于时保留。范围 `0–268435456`，整数；`0` 关闭过滤。比如 `4096` 就是 `64×64` 的面积。缩小后的图片也会检查。 | `ocu config set image.discardBelowPixelCount 4096` |
| `image.captureTimeout` | `5` | ScreenCaptureKit 后备截图的超时，单位秒，范围 `0.01–300`。 | `ocu config set image.captureTimeout 10` |
