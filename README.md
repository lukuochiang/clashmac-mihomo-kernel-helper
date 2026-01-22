
# 📦 ClashMac 专用 mihomo 内核版本管理工具

ClashMac mihomo Kernel Helper 是一个专注于 **mihomo 内核下载、管理、切换** 的命令行助手，避免重复下载、支持按时间戳管理备份，与 GUI 完全分离职责。

---

## 🔗 关联项目

- [ClashMac 项目地址](https://github.com/666OS/ClashMac)  
- 本仓库仅管理 **mihomo 内核**，不依赖 GUI，也不启动或控制内核运行状态

---

## 🧠 设计理念

**职责分离 → 工具稳定、可维护、可追溯**

- **脚本负责版本管理**  
  - 下载 mihomo 内核  
  - 按时间戳备份历史版本  
  - 切换指定版本  
  - 避免重复下载

- **GUI 负责运行内核**  
  - 启动/重启 mihomo  
  - 权限授权（防火墙、网络）  
  - 进程守护

---

## 📌 功能总览

| 命令                  | 功能                        |
| ------------------- | -------------------------- |
| `status`            | 显示当前核心 & 最新备份版本 |
| `list`              | 按时间戳降序列出所有备份    |
| `install [version]` | 下载/安装指定版本（默认最新） |
| `switch <version>`  | 切换到指定备份版本          |
| `help`              | 显示帮助说明               |

---

## 🚀 快速开始

1. 克隆仓库  

```bash
git clone https://github.com/lukuochiang/clashmac-mihomo-kernel-helper.git
cd clashmac-mihomo-kihomo-kernel-helper
```

2. 给脚本执行权限  

```bash
chmod +x clashmac_mihomo_kernel_helper.sh
```

3. 基本命令示例  

- 查看当前状态  

```bash
sh clashmac_mihomo_kernel_helper.sh status
```

输出示例：

```
当前使用核心:
  mihomo -> darwin-amd64-v1.19.9

最新备份:
  mihomo.backup.mihomo-darwin-amd64-v1.19.9.20260122_005337 -> darwin-amd64-v1.19.9 -> 20260122_005337

提示:
  sh clashmac_mihomo_kernel_helper.sh switch darwin-amd64-v1.19.9
```

- 列出所有备份  

```bash
sh clashmac_mihomo_kernel_helper.sh list
```

输出示例：

```
1) mihomo.backup.mihomo-darwin-amd64-alpha-xxxxxx.20260122_113554 -> darwin-amd64-alpha-xxxxxx -> 20260122_113554
2) mihomo.backup.mihomo-darwin-amd64-v1.19.9.20260122_005337 -> darwin-amd64-v1.19.9 -> 20260122_005337
```

- 安装最新或指定版本  

```bash
# 安装默认最新
sh clashmac_mihomo_kernel_helper.sh install

# 安装指定版本
sh clashmac_mihomo_kernel_helper.sh install v1.19.9
```

- 切换到某个备份版本  

```bash
sh clashmac_mihomo_kernel_helper.sh switch darwin-amd64-v1.19.9
```

> 切换后请前往 GUI（如 ClashMac）执行 **重启内核** 使其生效

---

## 🧩 版本解析规则

- 当前内核通过 `./mihomo -v` 获取版本  
- 备份文件按名称中的 **时间戳** 排序  
- 格式统一：  

```
mihomo.backup.mihomo-darwin-<arch>-<version>.<timestamp>
```

---

## ❗ FAQ

**Q: 为什么没有自动重启内核？**  
A: GUI 管理内核运行态更稳定，脚本只负责版本切换  

**Q: 为什么需要备份？**  
A: 避免误覆盖，可随时切换回旧版本  

**Q: 为什么按时间戳排序？**  
A: YYYYMMDD_HHMMSS 保证历史顺序，可追溯

---

## 📜 许可协议

本项目使用 **MIT License**  

允许：复制、修改、再发布、私有/商业用途  
不负责：完整性、后果、兼容性、责任  

详情见 LICENSE 文件
