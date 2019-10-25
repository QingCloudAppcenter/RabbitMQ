---
name: Release Checklist
about: Describe this issue template's purpose here.
title: ''
labels: ''
assignees: ''

---

# Changelog

## Features
- [x] New version haproxy keepalived rabbitmq

## Bug fixes
- [x] Reduce the risk of data loss

## Enhancements
- [ ] Enhancements

## Tech debt
- [ ] Tech debt

# 通用
- [ ] 关闭 SSH 服务
- [x] 清除 .bash_history（包括 ubuntu 和 root 用户）
- [x] 安装 arping 防止同网段虚机和 IP 地址频繁重建引起的问题（apt install iputils-arping）
- [x] TCP keepalive timeout（基础网络）

# 服务功能测试

- [x] 写入数据，自定义客户端正常读取
- [ ] 在配置项可自由开启zabbix-agent
- [ ] 在配置项中可自由开关caddy
- [x] confd升级到最新版本
- [ ] 通过浏览器查看服务日志
- [x] 日志轮转

# 集群功能测试

## 创建
- [x] 创建单个节点的集群
- [x] 创建多个节点的集群
- [x] 创建常用硬件配置的集群
- [x] 修改常用配置参数，创建集群

## 横向伸缩
- [x] 增加节点，数据正常
- [x] 删除节点

## 纵向伸缩
- [x] 扩容：服务正常
- [x] 缩容：服务正常

## 升级
- [x] 数据不丢
- [x] 升级后设置日志留存大小限制值，查看日志留存配置生效

## 其他
- [x] 关闭集群并启动集群
- [x] 删除集群并恢复集群
- [ ] 备份集群并恢复集群
- [ ] 支持多可用区
- [ ] 切换私有网络
- [x] 绑定公网 IP(vpc)
- [ ] 基础网络部署
- [x] 自动伸缩（节点数，硬盘容量）
- [x] 健康检查和自动重启
- [x] 服务监控