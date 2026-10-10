# Configuration

[English](configuration.md) | [简体中文](configuration.zh-CN.md)

The config file defaults to `~/.config/ocu/config.json`. You can edit it directly, or create it if it doesn't exist. Here are the defaults:

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

These settings currently apply to macOS screenshots. Changes take effect on the next capture. Environment variables are also supported, with precedence: ENV > config file > defaults.

## Configure from the command line

You can also use `ocu config`. Changes are saved to the file above:

```bash
# View settings
ocu config

# Switch to JPG
ocu config set image.format jpg

# Read one setting
ocu config get image.format

# Restore the default (ENV overrides still take priority)
ocu config reset image.format

# Show the config file path
ocu config path
```

You can use `open-computer-use` in place of `ocu`.

## Settings

| Setting | Default | Description | Example command |
| --- | --- | --- | --- |
| `image.format` | `png` | Output format: `png`, `jpg` or `webp`. WebP is lossless. | `ocu config set image.format webp` |
| `image.jpegQuality` | `0.8` | JPG quality, from `0` to `1`. Only affects JPG. | `ocu config set image.jpegQuality 0.9` |
| `image.maxLongEdgePixels` | `1280` | Maximum long edge in pixels. Integer `1–16384`; `null` disables the limit. | `ocu config set image.maxLongEdgePixels 1920` |
| `image.scaleDownAfterMaxSize` | `true` | If the long edge exceeds the limit, `true` resizes proportionally and `false` omits the screenshot. | `ocu config set image.scaleDownAfterMaxSize false` |
| `image.discardBelowPixelCount` | `64` | Omit when width × height is below this value; equality is retained. Integer `0–268435456`; `0` disables filtering. For example, `4096` is the area of `64×64`. Resized images are checked too. | `ocu config set image.discardBelowPixelCount 4096` |
| `image.captureTimeout` | `5` | ScreenCaptureKit fallback capture timeout, in seconds. Range `0.01–300`. | `ocu config set image.captureTimeout 10` |
