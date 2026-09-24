> macOS 不能直观显示耳机是否已连接，这个小工具补充这一状态。

[English](README.en.md) | [中文](README.md)

# Bluetooth Status

一个只读的 macOS 菜单栏工具，用来一眼确认蓝牙音频设备是否连接到 Mac。

## 功能

- 自动枚举所有已配对的蓝牙音频设备，不写死设备地址；
- 任意一个蓝牙音频设备连接时显示 `B`；
- 蓝牙音频设备都断开时显示带斜杠的 `B`；
- 没有发现音频设备或系统无法枚举时显示 `?`；
- 图标是显式绘制的矢量 `B`，不依赖系统模板图标或电池 API；
- 图标颜色自动采用菜单栏反色：深色菜单栏用白色，浅色菜单栏用黑色；
- 监听 IOBluetooth 专用连接 callback 和设备断开通知；
- 菜单中列出每个蓝牙音频设备及其状态；
- 支持立即刷新和退出；
- 为 VoiceOver 提供状态标签和状态值；
- 监听唤醒、应用激活、设备信息变化和外观变化。

## 连接状态逻辑

只读取：

```text
IOBluetoothDevice.pairedDevices()
device.nameOrAddress
device.addressString
device.isConnected()
```

设备筛选条件：

- 蓝牙 Device Class Major 为 Audio；或
- 设备报告 Hands-Free / Hands-Free Audio Gateway。

这个策略优先保证不漏掉耳机，代价是某些蓝牙音箱等音频设备也可能出现在列表中。

程序不会连接、断开、配对或修改任何蓝牙设备。

## 被动更新

不需要每两秒轮询。

App 启动时读取一次当前状态。连接使用 `IOBluetoothDevice.register(forConnectNotifications:selector:)`，断开使用 `IOBluetoothDeviceDisconnected` 通知；同时监听唤醒、应用激活、设备信息变化和外观变化。没有 2 秒轮询，只有 30 秒一次的故障恢复兜底。菜单中的“立即刷新”可手动重新读取。

## 构建

项目只需要 Command Line Tools，不需要完整 Xcode：

```sh
cd ~/make/bluetooth-status
make test
make
```

构建产物：

```text
build/BluetoothStatus.app
```

## 运行

```sh
cd ~/make/bluetooth-status
make run
```

或者手动打开：

```sh
open build/BluetoothStatus.app
```

App 使用 `LSUIElement`，不会显示 Dock 图标；启动后只在菜单栏显示状态图标。

## 命令行验证

```sh
make dump
```

输出类似：

```text
state=connected
status=已连接
connected=1
audio_devices=2
device=Redmi Buds 6 address=00:11:22:33:44:55 connected=true
device=Studio Headphones address=AA-BB-CC-DD-EE-FF connected=false
```

## 开机启动

已安装用户级 LaunchAgent：

```text
~/Library/LaunchAgents/com.justin.bluetoothstatus.plist
```

安装或更新 App 并同步开机启动配置。重复执行会覆盖 `/Applications/BluetoothStatus.app` 和 LaunchAgent，并重新加载 launchd：

```sh
cd ~/make/bluetooth-status
make install
```

这会将 App 安装到：

```text
/Applications/BluetoothStatus.app
```

并让 LaunchAgent 从该路径启动。

查看状态：

```sh
make login-item-status
```

卸载开机启动但保留 App：

```sh
make uninstall-login-item
```

卸载开机启动并删除 `/Applications/BluetoothStatus.app`：

```sh
make uninstall
```

LaunchAgent 使用当前用户的 `gui/$(id -u)` 域，不需要 `sudo`，不会影响其他用户。`KeepAlive` 只在异常退出时重启 App，用户正常退出不会被拉起。

## 隐私与行为边界

程序只调用公开的只读接口，不读取电池，不使用私有 API，不使用 `sudo`，也不修改蓝牙系统配置。安装由 `make install` 显式执行，安装脚本会先校验临时 App/plist，失败时尝试回滚旧版本。
