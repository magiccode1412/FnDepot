<div align="center">

# [FnDepot](https://github.com/magiccode1412/FnDepot) - 飞牛第三方应用仓库

<a href="https://github.com/magiccode1412/FnDepot" target="_blank">Github</a>

更新日期：2026-08-06

</div>


## 声明

+ 本仓库项目均以 docker 方式打包
+ 为了能快速下载 docker 镜像，故把作者发布的镜像搬运到我的仓库
+ 为了区分和溯源，所有应用名都会加上 `magic-` 前缀，介意勿用

## 源说明

+ 本仓库为 **FnDepot 外部应用源 V2** 格式（`fnpack.json` 含 `schema_version: "2"`）。
+ 添加方式：在 FnDepot 客户端中添加本仓库地址或 `fnpack.json` 直链。
+ 源信息：名称「魔法领域」，维护者「魔法代码」。
+ 安装包与图标通过 `packages/`、`assets/icons/` 目录提供，并附 `sha256` 与字节级 `size`。

## ⚠️特别说明⚠️

+ 由于部分应用设置 `X-Frame-Options` 为 `sameorigin`，故以下应用无法实现在飞牛 web 端打开：
  + 青龙面板
  + uptime-kuma

## 应用列表

| 应用 | 版本 | 平台 | 分类 | 简介 | 维护者 |
|------|------|------|------|------|--------|
| [日志推送](#日志推送) | 2.3.0 | all | 系统工具 | 飞牛日志监控机器人，支持企业微信/钉钉/飞书/Bark/PushPlus 等多渠道推送 | Lando |
| [bililivego](#bililivego) | 0.7.39 | all | 影音娱乐 | 支持多种直播平台的直播录制工具 | bililive-go |
| [bilisync](#bilisync) | 2.11.1 | all | 影音娱乐 | 专为 NAS 用户编写的哔哩哔哩同步工具（Rust & Tokio 驱动） | amtoaer |
| [ddnsgo](#ddnsgo) | 6.17.2 | all | 系统工具 | 自动获得公网 IPv4/IPv6 地址并解析到对应域名服务 | jeessy2 |
| [qiandao](#qiandao) | 1.0.0 | all | 生活服务 | HTTP 请求定时任务自动执行框架（基于 HAR Editor 和 Tornado Server） | qd-today |
| [青龙面板](#青龙面板) | 2.21.0 | all | 系统工具 | 支持 Python3/JavaScript/Shell/TypeScript 的定时任务管理平台 | whyour |
| [speedtest](#speedtest) | 6.1.0 | all | 系统工具 | 轻量级网络速度测试工具（JavaScript 实现） | librespeed |
| [splayer](#splayer) | 3.1.1 | all | 影音娱乐 | 简约的音乐播放器 | imsyy |
| [uptime-kuma](#uptime-kuma) | 2.4.0 | all | 系统工具 | 易于使用的自托管监控工具 | louislam |

---

## 应用详情

### 日志推送

- **版本**: 2.3.0
- **平台**: all
- **分类**: 系统工具
- **维护者**: [Lando](https://github.com/Sunanang/FNMessageBots)
- **分发者**: [魔法代码](https://github.com/magiccode1412/)
- **简介**: 飞牛日志监控机器人，专注于实时监控系统事件，精准捕捉关键动态，确保异常与重要信息不遗漏。支持企业微信、钉钉、飞书、Bark、PushPlus 等多种渠道灵活推送通知，让系统消息实时触达、一目了然，帮助您随时随地掌握系统运行状态。

### bililivego

- **版本**: 0.7.39
- **平台**: all
- **分类**: 影音娱乐
- **维护者**: [bililive-go](https://github.com/bililive-go/bililive-go)
- **分发者**: [魔法代码](https://github.com/magiccode1412/)
- **简介**: 一个支持多种直播平台的直播录制工具。

### bilisync

- **版本**: 2.11.1
- **平台**: all
- **分类**: 影音娱乐
- **维护者**: [amtoaer](https://github.com/amtoaer/bili-sync)
- **分发者**: [魔法代码](https://github.com/magiccode1412/)
- **简介**: bili-sync 是一款专为 NAS 用户编写的哔哩哔哩同步工具，由 Rust & Tokio 驱动。

### ddnsgo

- **版本**: 6.17.2
- **平台**: all
- **分类**: 系统工具
- **维护者**: [jeessy2](https://github.com/jeessy2/ddns-go)
- **分发者**: [魔法代码](https://github.com/magiccode1412)
- **简介**: 自动获得你的公网 IPv4 或 IPv6 地址，并解析到对应的域名服务。

### qiandao

- **版本**: 1.0.0
- **平台**: all
- **分类**: 生活服务
- **维护者**: [qd-today](https://github.com/qd-today/qd)
- **分发者**: [魔法代码](https://github.com/magiccode1412)
- **简介**: 一个 HTTP 请求定时任务自动执行框架，基于 HAR Editor 和 Tornado Server。

### 青龙面板

- **版本**: 2.21.0
- **平台**: all
- **分类**: 系统工具
- **维护者**: [whyour](https://github.com/whyour/qinglong)
- **分发者**: [魔法代码](https://github.com/magiccode1412)
- **简介**: 支持 Python3、JavaScript、Shell、Typescript 的定时任务管理平台。

### speedtest

- **版本**: 6.1.0
- **平台**: all
- **分类**: 系统工具
- **维护者**: [librespeed](https://github.com/librespeed/speedtest)
- **分发者**: [魔法代码](https://github.com/magiccode1412)
- **简介**: 一个非常轻量级的速度测试工具，用 Javascript 实现，使用 XMLHttpRequest 和 Web Workers。

### splayer

- **版本**: 3.1.1
- **平台**: all
- **分类**: 影音娱乐
- **维护者**: [imsyy](https://github.com/imsyy/SPlayer)
- **分发者**: [魔法代码](https://github.com/magiccode1412/)
- **简介**: 一个简约的音乐播放器。

### uptime-kuma

- **版本**: 2.4.0
- **平台**: all
- **分类**: 系统工具
- **维护者**: [louislam](https://github.com/louislam/uptime-kuma)
- **分发者**: [魔法代码](https://github.com/magiccode1412)
- **简介**: Uptime Kuma 是一款易于使用的自托管监控工具。
