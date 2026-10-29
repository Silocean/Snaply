# Snaply

这台 Mac 上的菜单栏截屏。选区、窗口和像素都交给系统 `screencapture`。

## 构建

```bash
./build.sh
```

构建结果在 `build.noindex/`，聚焦不会索引它。装到本机的是 `/Applications/Snaply.app`。

## 使用

```bash
open /Applications/Snaply.app
```

截图后先在屏幕上编辑：矩形、椭圆、箭头、画笔、文字，再复制或保存。不会自动进剪贴板。保存的默认目录是 `~/Pictures/Snaply`。

命令行：

```bash
/Applications/Snaply.app/Contents/MacOS/Snaply region
/Applications/Snaply.app/Contents/MacOS/Snaply screen --silent -o ~/Desktop
```

第一次截屏时，系统会要求允许屏幕录制。
