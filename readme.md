<div align="center">

# [FnDepot](https://github.com/magiccode1412/FnDepot) - 飞牛第三方应用仓库

<a href="https://github.com/magiccode1412/FnDepot" target="_blank">Github</a>

更新日期：2026-08-06

</div>


## 声明

+ 本仓库项目均以 docker 方式打包
+ 为了能快速下载 docker 镜像，故把作者发布的镜像搬运到我的仓库
+ 为了区分和溯源，所有应用名都会加上 `magic-` 前缀，介意勿用

## ⚠️特别说明⚠️

+ 由于部分应用设置 `X-Frame-Options` 为 `sameorigin`，故以下应用无法实现在飞牛 web 端打开：
  + 青龙面板
  + uptime-kuma

## 应用列表

| 应用 | 版本 | 平台 | 简介 | 维护者 |
|------|------|------|------|--------|
| [日志推送](#日志推送) | 2.3.0 | all | 飞牛日志监控机器人，支持企业微信/钉钉/飞书/Bark/PushPlus 等多渠道推送 | [Lando](https://github.com/Sunanang/FNMessageBots) |
| [bililivego](#bililivego) | 0.7.39 | all | 支持多种直播平台的直播录制工具 | [bililive-go](https://github.com/bililive-go/bililive-go) |
| [bilisync](#bilisync) | 2.11.1 | all | 专为 NAS 用户编写的哔哩哔哩同步工具（Rust & Tokio 驱动） | [amtoaer](https://github.com/amtoaer/bili-sync) |
| [ddnsgo](#ddnsgo) | 6.17.2 | all | 自动获得公网 IPv4/IPv6 地址并解析到对应域名服务 | [jeessy2](https://github.com/jeessy2/ddns-go) |
| [qiandao](#qiandao) | 1.0.0 | all | HTTP 请求定时任务自动执行框架（基于 HAR Editor 和 Tornado Server） | [qd-today](https://github.com/qd-today/qd) |
| [青龙面板](#青龙面板) | 2.21.0 | all | 支持 Python3/JavaScript/Shell/TypeScript 的定时任务管理平台 | [whyour](https://github.com/whyour/qinglong) |
| [speedtest](#speedtest) | 6.1.0 | all | 轻量级网络速度测试工具（JavaScript 实现） | [librespeed](https://github.com/librespeed/speedtest) |
| [splayer](#splayer) | 3.1.1 | all | 简约的音乐播放器 | [imsyy](https://github.com/imsyy/SPlayer) |
| [uptime-kuma](#uptime-kuma) | 2.4.0 | all | 易于使用的自托管监控工具 | [louislam](https://github.com/louislam/uptime-kuma) |

---
