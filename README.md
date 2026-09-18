# AndroidTransmit

原生 SwiftUI macOS 应用，通过 USB MTP 在 Mac 和 Android 之间传输文件。首版面向当前 Apple Silicon / macOS 27 开发环境，无需 USB 调试或手机端 App。

## 构建和运行

需要 Xcode 27、Homebrew，以及 libmtp / libusb。

```sh
brew install libmtp
./script/build_and_run.sh
```

本机 Homebrew 在 macOS 27 预览版上出现 bottle 清单和依赖检测错误，因此实际验证使用项目内编译的 **libmtp 1.1.23**，动态链接 Homebrew 的 **libusb 1.0.29**。以下脚本验证源码 SHA-256 后构建到 `.build/native`，不修改 Homebrew 中已有的库：

```sh
./script/setup_dependencies.sh
./script/build_and_run.sh --verify
```

源码优先复用 Homebrew 下载缓存，否则从 libmtp 官方 SourceForge 下载。需要已安装 `libusb` 和 `pkgconf`。项目内库优先于 Homebrew libmtp；`.build/native` 是运行依赖，请勿在运行时删除或移动项目目录。它不是可独立分发的安装包。

Codex 的 Run 按钮已指向构建启动脚本。脚本支持 `--build`、`--verify`、`--debug`、`--logs`、`--telemetry`；`CONFIGURATION=Release ./script/build_and_run.sh --build` 构建 Release。启动脚本会结束现有 AndroidTransmit 进程，请勿在传输期间重新运行脚本。应用使用本机 ad-hoc 签名，开启 Hardened Runtime，关闭 App Sandbox，并允许加载本机的第三方动态库。

## 使用

1. 使用支持数据的 USB 线连接手机，解锁，选择“文件传输 / MTP”，允许文件访问。
2. 左侧选择设备与存储空间；双击文件夹进入，路径栏可返回任意上级。
3. 点击上传，或从 Finder 拖入文件/文件夹；选中手机项目后点击下载并选择 Mac 文件夹。
4. 通过工具栏或右键菜单新建、重命名、删除。删除是永久删除，不进入 Mac 废纸篓。
5. “更多”菜单选择同名策略：默认保留两者，或跳过；不会覆盖现有文件。同名目录整体另取名称或跳过，不合并。
6. 底部队列可取消、重试和清除已结束任务。传输期间暂停目录及其他设备操作，保持单一 MTP 会话串行执行。

快捷键：⌘R 刷新，⇧⌘U 上传，⇧⌘D 下载，⇧⌘N 新建文件夹；表格支持多选、列排序、删除命令和当前目录名称过滤。

## 数据与错误处理

- 下载写入同目录的随机临时文件；核对字节数并写入磁盘后，以不覆盖现有文件的原子操作提交。失败或取消时移除临时文件。
- 上传中断后尝试清理本次不完整文件。设备未返回对象编号或清理失败时，任务提示检查残留文件。
- 文件夹传输中断时保留已经完成的文件并提示目录可能不完整。重试从头开始，遵循同名策略，不支持续传。
- 拒绝符号链接和特殊本地文件；含链接的目录在准备阶段失败，不跟随链接。远端名称拒绝路径分隔符、冒号、NUL、`.` 与 `..`。
- USB 移除时取消队列并释放会话；重连后按保存的目录路径重新解析对象编号。具有 USB 序列号的设备可跨端口识别，没有序列号则使用同一 USB 端口作为身份依据。
- 仅能访问手机通过 MTP 暴露的目录。锁屏、受保护目录、设备忙和空间不足等错误显示在界面，不当作成功。
- 可用容量为连接时读取的存储快照；重新连接设备可更新。传输任务仅保留在内存中。

## 验证

```sh
./script/test.sh                 # 模拟服务测试
./script/test.sh --probe         # 只读真机设备/存储探测
./script/test.sh --device-smoke  # 真机往返与取消测试
```

真机脚本会在第一台手机的第一个存储中创建 `AndroidTransmit-Test-UUID` 目录，上传测试文件、下载并核对 SHA-256、验证重命名和删除，仅清理本次生成的目录。测试中途拔线或强制退出可能留下这个目录，需要手动清理。运行真机脚本前应退出其他 MTP 应用以避免竞争访问。

自动化检查覆盖同名规则、危险路径、递归上传下载、空文件、符号链接、失败清理、串行队列、取消、失败重试、断线状态和重连后对象重新解析。实际运行结果及尚未完成的人工场景见 [VALIDATION.md](VALIDATION.md)。

首版不包含无线连接、同步备份、图片预览、Finder 挂载、队列持久化、暂停续传或商店发布。

## 第三方依赖

- [libmtp 1.1.23](https://github.com/libmtp/libmtp)：LGPL-2.1-or-later，源码与许可保留于 `.build/dependencies/libmtp-1.1.23`。
- [libusb 1.0.29](https://github.com/libusb/libusb)：LGPL-2.1-or-later，本机 Homebrew 安装的 `COPYING` 位于 `/opt/homebrew/opt/libusb/COPYING`。

应用动态链接这些库，未修改第三方源码。未来对外分发需另外完成依赖随包发布、对应源码/许可、正式签名与公证。
