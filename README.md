# 🐈 BigCat **A**

一键代理节点搭建：网页点选协议 → 生成 SSH 命令 → 粘贴到服务器回车一次搞定。

对标参考：甬哥 yonggekkk 的 [argosbx](https://github.com/yonggekkk/argosbx) 与其命令生成器网页（变量名与快捷命令保持兼容，旧 agsbx / argosbx 命令可直接粘回本页改配）。

## 组成

| 部分 | 状态 | 说明 |
|---|---|---|
| `index.html` 网页命令生成器 | ✅ v0.1.0 上线 | 单文件、零依赖、纯本地生成不上传；GitHub Pages：https://zhanghaobo1987.github.io/BigCat-A/ |
| `bigcata.sh` 主脚本 | ✅ v0.3.0 | Sing-box + Xray + Cloudflared-Argo 三内核，按网页生成的环境变量无交互安装；本机实测 6 协议端到端穿透通过 |
| 发布流水线 `bigcata_release.py` | ✅ 已就绪 | 在维护机 `~/workspace/tools/`（与家族其他发布工具同处）；照家族规矩：测试 → 升 VERSION → GitHub Release → 外网验证 |

## 生成器功能（v0.1.0）

- 14 种协议勾选 + 端口（留空随机）：Xray（vlpt/xhpt/vxpt/vwpt/xupt/xcpt）、Sing-box（tupt/anpt/nvpt/arpt/sspt）、自动分配（hypt/vmpt/sopt）
- 全局项：uuid（含一键生成）、reym、cfip、alns（开启后才可选 Naiveproxy）、hyjpt、cdnym、warp 15 种组合、ippz、oap、name
- 订阅：sub / subid / subpt；Argo：argo=vwpt|vmpt、agn、agk（固定隧道）
- 联动禁用：Reality 域名仅 Reality 协议时可用、端口跳跃仅 Hy2 时可用、订阅/Argo 子项仅开启后可用，与参考页一致
- 快捷预设：极简直连、Sing-box 全家桶、全协议、Argo 免公网、CDN 优选、带订阅
- 双向编辑：改表单即时生成命令；把旧命令粘回输出框自动解析回表单
- 快捷命令：list / rep / res / upx / ups / upa / del（list 保留 ippz，rep 带当前全部变量）
- 校验：端口非数字/超范围报错、重复端口提醒、未选协议提醒；含空格的值自动加引号
- curl / wget 切换、深/浅色（localStorage 记忆）、复制到剪贴板

## 脚本地址

页面顶部 JS 常量 `SCRIPT_URL` 一处配置，当前指向：
`https://raw.githubusercontent.com/zhanghaobo1987/BigCat-A/main/bigcata.sh`
（仓库 `zhanghaobo1987/BigCat-A` 为公开仓库；主脚本 `bigcata.sh` 已发布，该地址已生效。）

## 本地预览

```bash
cd ~/workspace/bigcat-a && python3 -m http.server 8898 --bind 127.0.0.1
# 浏览器打开 http://127.0.0.1:8898/
```

版本源：`VERSION` 文件（当前 0.3.1）。

## 部署点

- GitHub Pages（主）：https://zhanghaobo1987.github.io/BigCat-A/
- LightLayer 同步：http://207.57.182.4:8905/（/opt/bigcat-a，systemd 服务 bigcat-a，发版时同步更新并外网验证）

## 主脚本用法

```bash
# 勾选式安装（变量出现即启用，空值=随机端口，与网页生成器一致）
vlpt=443 hypt=8443 tupt="" sspt="" sub=y bash <(curl -Ls https://raw.githubusercontent.com/zhanghaobo1987/BigCat-A/main/bigcata.sh)

bigcata list   # 显示节点与订阅
bigcata rep    # 带新变量重置/更新（密钥与端口默认保留）
bigcata res    # 重启
bigcata upx    # 升级 Xray（ups=sing-box，upa=cloudflared）
bigcata del    # 卸载
```

实测（v0.3.0，本机）：vlpt/hypt/tupt/sspt/vmpt/sopt 六协议客户端端到端穿透 HTTP 200；其余协议（xhpt/vxpt/vwpt/xupt/xcpt/anpt/nvpt/arpt）配置经内核官方校验通过。
已知简化：WARP 只区分内核粒度（不细分 v4/v6 组合）；alns 域名证书未接入（nvpt 等先用自签证书，客户端需允许不安全证书）。
