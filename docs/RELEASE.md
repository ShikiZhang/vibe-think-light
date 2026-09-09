# 准备可下载版本

维护者在 Apple Silicon macOS 的干净 checkout 中运行：

```sh
./test.sh
./Firmware/setup.sh
./Firmware/build-firmware.sh
python3 scripts/package-source.py
# 在仓库根目录打包 app，排除 resource fork 元数据
ditto -c -k --norsrc --keepParent 'dist/Keyboard Light.app' dist/Keyboard-Light-macOS-arm64.zip
(cd dist && shasum -a 256 Keyboard-Light-macOS-arm64.zip think65v3-keyboard-light.bin vibe-think-light-corresponding-source.tar.gz > SHA256SUMS)
```

`package-source.py` 只包括 Git index 中的项目文件；先暂存准备发布的源码。发布前用 `git diff --cached` 核对，确保不包含用户目录、日志、配置备份或凭据。

GitHub Release 应同时附上这 4 个文件，绑定产生这些产物的源码提交。说明键盘只支持 Think6.5 V3、Mac 架构、未经 Apple 公证，以及实测/未测范围。为其他型号自行构建不属于本项目支持范围。

对应源码包含 QMK 和全部参与编译的子模块源文件与许可证。不能仅依赖一个上游链接来代替在同一次二进制发布中提供相应源码。上传后再次核对附件名/大小和 SHA256SUMS。

更新日常灯光或通知 JSON 不需要固件发布；只有协议或固件实现改变时才需要重新刷入。不要在发布脚本中增加自动 Boot/自动刷机。
