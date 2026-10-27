# 🐈 BigCat **A**

一键代理节点搭建：网页点选协议 → 生成 SSH 命令 → 粘贴到服务器回车一次搞定。

对标参考：甬哥 yonggekkk 的 [argosbx](https://github.com/yonggekkk/argosbx) 与其命令生成器网页（变量名与快捷命令保持兼容，旧 agsbx / argosbx 命令可直接粘回本页改配）。

## 组成

| 部分 | 状态 | 说明 |
|---|---|---|
| `index.html` 网页命令生成器 | ✅ v0.1.0 上线 | 单文件、零依赖、纯本地生成不上传；GitHub Pages：https://zhanghaobo1987.github.io/BigCat-A/ |
| `bigcata.sh` 主脚本 | ⏳ 下一步 | Sing-box + Xray + Cloudflared-Argo 三内核，按网页生成的环境变量无交互安装 |
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
（仓库 `zhanghaobo1987/BigCat-A` 已建为公开仓库；主脚本 `bigcata.sh` 发布后该地址即生效。）

## 本地预览

```bash
cd ~/workspace/bigcat-a && python3 -m http.server 8898 --bind 127.0.0.1
# 浏览器打开 http://127.0.0.1:8898/
```

版本源：`VERSION` 文件（当前 0.1.1）。
