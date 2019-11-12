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
- [x] Log online viewer

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
- [x] 在配置项中可自由开关caddy
- [x] confd升级到最新版本
- [x] 通过浏览器查看服务日志
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
- [x] 支持多可用区
- [ ] 切换私有网络
- [x] 绑定公网 IP(vpc)
- [ ] 基础网络部署
- [x] 自动伸缩（节点数，硬盘容量）
- [x] 健康检查和自动重启
- [x] 服务监控


## high available test
- [x] cluster_partition_handling=ignore。在生产者向node x 上生产消息的同时，模拟网络分区，对node x 进行断网（如卸载网卡），此时现象为集群其他mirror queue无法收取消息（需要提醒客户尽量做好message ack），但是切换生产者向其他节点发送消息，集群正常收取消息（除 node x外），但是此时web界面信息并不会更改，会停留在node x离开集群时的数字，实际上命令行已经可以查询number of messages 在增长，再恢复node x的网络，会发现在从master上拉取 `全部` 信息。同步完成后会恢复正常，但master不再切回。
- [x] 在mirror queue 状态为asyning时，memory消耗变大，会出现资源警告，web界面会飘红，此时链接会被切断，可以调整vm_memory_high_watermark 但如果设置不合理，将导致不断重启
- [x] cluster_partition_handling=ignore。在生产者向node x 上生产消息的同时，模拟网络分区，对node x 进行断网（仅将node x 与集群隔离开，集群状态显示x down, 但x仍实际存活），此时现象为集群正常收取消息，发起两个生产者p1,p2, p1向node x 生产消息，p2 向集群内其他机器生产消息，分别生产一段时间后，两个分区的message信息已经不同，再恢复node x的网络，会发现在web界面上提示“Network partition detected....”， 且集群上node x显示not running, 但在node x上显示其他机器not running。此时需要手动处理冲突。
- [x] cluster_partition_handling=pause_minority. 在生产者向node x 上生产消息的同时，模拟网络分区，对node x 进行断网（仅将node x 与集群隔离开，集群状态显示x down, 但x已经无法启动），此时现象为集群其他节点正常收取消息，web也更新，但mirror queue数减1，向集群其他存活节点生产一段时间后，再恢复node x的网络，web界面显示“Network partition detected.....”,一段时间之后会node x信息会同步到最新。
- [x] cluster_partition_handling=autoheal(从pause_minority切换过来时发现偶然数据丢失，但未能复现)，在生产者向node x 上生产消息的同时，模拟网络分区，对node x 进行断网（仅将node x 与集群隔离开，集群状态显示x down, 但x仍实际存活），此时现象为集群所有节点正常收取消息（会有一段时间的不可用），发起两个生产者p1,p2, p1向node x 生产消息，p2 向集群内其他机器生产消息，分别生产一段时间后，两个分区的message信息已经不同，两者可单独使用。再恢复node x的网络，发现node x 会去同步其他节点的信息，即使node x 上的信息更多更新。

> iptables command
> https://wangchujiang.com/linux-command/c/iptables.html
> MQ memory use guide
> https://www.rabbitmq.com/memory.html
> mirror queue guide
> https://www.rabbitmq.com/ha.html  https://www.jianshu.com/p/f917067bcee3