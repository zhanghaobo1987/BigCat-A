#!/bin/bash
# 🐈 BigCat A — 一键代理节点搭建脚本（Sing-box + Xray + Cloudflared-Argo）
# 用法：vlpt=443 hypt=8443 ... bash bigcata.sh [list|del|res|rep|upx|ups|upa]
# 变量与 argosbx 兼容：变量“出现即启用”，值为空表示随机端口。
export LANG=en_US.UTF-8
VER="0.4.3"
DIR="$HOME/bigcata"; BIN="$DIR/bin"; CONF="$DIR/conf"; SUBD="$DIR/sub"
PLAN="$DIR/plan.env"
URL_RAW="https://raw.githubusercontent.com/zhanghaobo1987/BigCat-A/main/bigcata.sh"
mkdir -p "$BIN" "$CONF" "$SUBD"

say(){ echo -e "\033[32m$*\033[0m"; }
warn(){ echo -e "\033[33m$*\033[0m"; }
err(){ echo -e "\033[31m$*\033[0m"; }

PROTOS="vlpt xhpt vxpt vwpt xupt xcpt tupt anpt nvpt arpt sspt hypt vmpt sopt"
# ---------- 旧配置（rep/list 时保留密钥与端口） ----------
declare -A OLD
if [ -f "$PLAN" ]; then while IFS='=' read -r k v; do OLD[$k]="$v"; done < "$PLAN"; fi

# ---------- 工具函数 ----------
arch(){ case $(uname -m) in aarch64|arm64) echo arm64;; x86_64|amd64) echo amd64;; *) err "不支持的架构 $(uname -m)"; exit 1;; esac; }
have(){ command -v "$1" >/dev/null 2>&1; }
port_used(){ (ss -tuln 2>/dev/null || netstat -tuln 2>/dev/null) | grep -q "[:.]$1[[:space:]]"; }
rand_port(){ local p i=0; while [ $i -lt 60 ]; do p=$(( (RANDOM % 40000) + 15000 )); port_used $p || { echo $p; return; }; i=$((i+1)); done; echo 0; }
resolve_port(){ # $1=var名 $2=旧值：显式值 > 旧值 > 随机
  local v="${!1:-}"
  if [ -n "$v" ]; then echo "$v"; elif [ -n "$2" ]; then echo "$2"; else rand_port; fi; }
dl(){ # $1=url $2=out
  if have curl; then curl -Ls --retry 3 -o "$2" "$1"; elif have wget; then wget -q --tries=3 -O "$2" "$1"; else err "缺少 curl/wget"; exit 1; fi; }
gh_latest_tag(){ curl -Ls "https://api.github.com/repos/$1/releases/latest" 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/'; }
extract_zip(){ # $1=zip $2=目标目录：unzip -> python3 -> busybox -> 装 unzip 再试
  mkdir -p "$2"
  if have unzip; then unzip -o -q "$1" -d "$2" && return 0; fi
  if have python3; then python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$1" "$2" && return 0; fi
  if have busybox; then busybox unzip -o "$1" -d "$2" >/dev/null 2>&1 && return 0; fi
  if have apt-get; then sudo apt-get update -y >/dev/null 2>&1; sudo apt-get install -y unzip >/dev/null 2>&1;
  elif have apk; then sudo apk add --no-cache unzip >/dev/null 2>&1; fi
  have unzip && unzip -o -q "$1" -d "$2"
}
extract_tgz(){ # $1=tgz $2=目标目录：tar -> python3
  mkdir -p "$2"
  if have tar; then tar -xzf "$1" -C "$2" && return 0; fi
  if have python3; then python3 -c "import tarfile,sys; tarfile.open(sys.argv[1]).extractall(sys.argv[2])" "$1" "$2" && return 0; fi
  return 1
}
ensure_python(){
  have python3 && return
  warn "未发现 python3，尝试安装…"
  if have apt-get; then sudo apt-get update -y >/dev/null 2>&1; sudo apt-get install -y python3 >/dev/null 2>&1;
  elif have apk; then sudo apk add --no-cache python3 >/dev/null 2>&1;
  elif have yum; then sudo yum install -y python3 >/dev/null 2>&1; fi
  have python3 || { err "python3 安装失败，脚本需要它生成配置"; exit 1; }
}
sudo(){ if [ "$(id -u)" = 0 ]; then "$@"; else command sudo "$@"; fi; }
HAS_SYSTEMD=0; [ -d /run/systemd/system ] && have systemctl && HAS_SYSTEMD=1

# ---------- 下载内核 ----------
install_sb(){
  local a=$(arch) v url
  # 钉版：1.14.1+ 的 Reality 与小火箭不兼容（实测断点），sbv=latest 可强制最新
  v="${sbv:-1.14.0}"; [ "$v" = latest ] && { v=$(gh_latest_tag SagerNet/sing-box); [ -z "$v" ] && v="1.14.0"; }
  url="https://github.com/SagerNet/sing-box/releases/download/v$v/sing-box-$v-linux-$a.tar.gz"
  say "下载 sing-box v$v ($a)…"; dl "$url" /tmp/sb.tgz || return 1
  extract_tgz /tmp/sb.tgz /tmp && cp /tmp/sing-box-$v-linux-$a/sing-box "$BIN/sb.new" && chmod +x "$BIN/sb.new" && mv -f "$BIN/sb.new" "$BIN/sb" && "$BIN/sb" version | head -1
}
install_xr(){
  local a=$(arch) v url zip="Xray-linux-64.zip"
  [ "$a" = arm64 ] && zip="Xray-linux-arm64-v8a.zip"
  # 钉版：26.9+ 的 Reality 与小火箭不兼容（实测 26.7.28 可用），xrv=latest 可强制最新
  v="${xrv:-26.7.28}"; [ "$v" = latest ] && { v=$(gh_latest_tag XTLS/Xray-core); [ -z "$v" ] && v="26.7.28"; }
  url="https://github.com/XTLS/Xray-core/releases/download/v$v/$zip"
  say "下载 Xray v$v ($a)…"; dl "$url" /tmp/xr.zip || return 1
  rm -rf /tmp/xrun && extract_zip /tmp/xr.zip /tmp/xrun && cp /tmp/xrun/xray "$BIN/xr.new" && chmod +x "$BIN/xr.new" && mv -f "$BIN/xr.new" "$BIN/xr" && "$BIN/xr" version | head -1
}
install_cf(){
  local a=$(arch)
  say "下载 cloudflared ($a)…"
  dl "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$a" "$BIN/cf.new" && chmod +x "$BIN/cf.new" && mv -f "$BIN/cf.new" "$BIN/cf" && "$BIN/cf" --version
}

# ---------- 服务管理 ----------
svc_write(){ # $1=名 $2=ExecStart
  if [ "$HAS_SYSTEMD" = 1 ]; then
    sudo tee /etc/systemd/system/bigcata-$1.service >/dev/null <<EOF
[Unit]
Description=BigCat A $1
After=network.target
[Service]
ExecStart=$2
WorkingDirectory=$DIR
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload; sudo systemctl enable -q bigcata-$1 2>/dev/null
  fi
}
svc_start(){
  if [ "$HAS_SYSTEMD" = 1 ]; then sudo systemctl restart bigcata-$1;
  else
    case "$1" in
      sb|xr) pkill -f "$BIN/$1 run" 2>/dev/null;;
      argo) pkill -f "$BIN/cf tunnel" 2>/dev/null;;
      sub) pkill -f "http.server.*$SUBD" 2>/dev/null;;
    esac
    sleep 1
    nohup $2 >"$DIR/$1.log" 2>&1 &
  fi
}
svc_stop(){
  if [ "$HAS_SYSTEMD" = 1 ]; then sudo systemctl stop bigcata-$1 2>/dev/null; sudo systemctl disable -q bigcata-$1 2>/dev/null; sudo rm -f /etc/systemd/system/bigcata-$1.service; sudo systemctl daemon-reload;
  else pkill -f "bigcata.*$1" 2>/dev/null; pkill -f "$BIN/$1" 2>/dev/null; fi
}

do_del(){
  say "卸载 BigCat A…"
  for s in sb xr argo sub; do svc_stop $s; done
  pkill -f "$BIN/sb" 2>/dev/null; pkill -f "$BIN/xr" 2>/dev/null; pkill -f "$BIN/cf" 2>/dev/null
  pkill -f "http.server.*$SUBD" 2>/dev/null
  if have iptables; then sudo iptables -t nat -D PREROUTING -j BIGCATA_HOP 2>/dev/null; sudo iptables -t nat -F BIGCATA_HOP 2>/dev/null; sudo iptables -t nat -X BIGCATA_HOP 2>/dev/null; fi
  sudo rm -f /usr/local/bin/bigcata
  rm -rf "$DIR"
  say "已卸载完成。"
}
do_res(){
  [ -f "$PLAN" ] || { err "未安装（无 plan.env）"; exit 1; }
  for s in sb xr argo sub; do [ -f /etc/systemd/system/bigcata-$s.service ] && sudo systemctl restart bigcata-$s 2>/dev/null; done
  say "已重启（systemd 服务按启用状态重启；nohup 模式请重新运行安装命令）。"
}

# ---------- 快捷命令分发 ----------
case "$1" in
  del) do_del; exit 0;;
  res) do_res; exit 0;;
  list) ;; # 落到文末 list 生成（需要 plan）
  upx|ups|upa)
    [ -f "$PLAN" ] || { err "未安装"; exit 1; }
    case "$1" in upx) install_xr;; ups) install_sb;; upa) install_cf;; esac
    for s in sb xr argo; do [ -f /etc/systemd/system/bigcata-$s.service ] && sudo systemctl restart bigcata-$s 2>/dev/null; done
    say "内核已升级并重启。"; exit 0;;
  rep) : ;; # 与安装同流程（旧值保留）
  "") : ;;
  *) err "未知命令：$1（可用 list/del/res/rep/upx/ups/upa）"; exit 1;;
esac

# ---------- list：仅根据 plan 重新打印 ----------
if [ "$1" = "list" ]; then
  [ -f "$PLAN" ] || { err "未安装（找不到 $PLAN）"; exit 1; }
  ensure_python
  ARGO_DOMAIN_FILE="$DIR/argo-domain.txt" python3 - "$PLAN" <<'PYEOF'
import os, sys
plan = {}
for line in open(sys.argv[1], encoding='utf-8'):
    line = line.rstrip('\n')
    if '=' in line:
        k, v = line.split('=', 1); plan[k] = v
plan['ARGO_DOMAIN'] = ''
f = os.environ.get('ARGO_DOMAIN_FILE', '')
if f and os.path.exists(f):
    plan['ARGO_DOMAIN'] = open(f).read().strip()
exec(open(os.path.join(os.path.dirname(sys.argv[1]), 'gen.py'), encoding='utf-8').read())
print_links(plan)
PYEOF
  exit 0
fi

# ---------- 安装主流程 ----------
# 至少一个协议（rep 时可沿用旧协议集）
ANY=0; for p in $PROTOS; do [ -n "${!p+x}" ] && ANY=1; done
if [ "$ANY" = 0 ]; then
  if [ "$1" = "rep" ] && [ -n "${OLD[protos]:-}" ]; then
    for p in ${OLD[protos]}; do declare "$p=${OLD[port_$p]:-}"; done
  else
    err "请至少设置一个协议变量，例如：vlpt=443 hypt=8443 bash <(curl -Ls $URL_RAW)"; exit 1
  fi
fi
ensure_python
say "🐈 BigCat A v$VER 开始安装…"

# IP 探测
IP4=$(curl -s4m5 https://icanhazip.com 2>/dev/null || curl -s4m5 https://ip.sb 2>/dev/null)
IP6=$(curl -s6m5 https://icanhazip.com 2>/dev/null)
IP_SHOW="$IP4"; [ "${ippz:-}" = "6" ] && IP_SHOW="$IP6"; [ -z "$IP_SHOW" ] && IP_SHOW="${IP4:-$IP6}"
[ -z "$IP_SHOW" ] && IP_SHOW="YOUR_IP"
HOST_SHOW="$IP_SHOW"; case "$IP_SHOW" in *:*) HOST_SHOW="[$IP_SHOW]";; esac

# 需要哪些内核
NEED_SB=0; NEED_XR=0
for p in tupt anpt nvpt arpt sspt hypt; do [ -n "${!p+x}" ] && NEED_SB=1; done
for p in vlpt xhpt vxpt vwpt xupt xcpt vmpt sopt; do [ -n "${!p+x}" ] && NEED_XR=1; done
[ "${argo:-}" != "" ] && NEED_CF=1 || NEED_CF=0

# 每次安装都拉官方最新内核；下载失败才沿用已装版本兜底（无已装版本则报错退出）
fetch_kernel(){ # $1=显示名 $2=二进制名 $3=安装函数
  if [ -x "$BIN/$2" ]; then say "更新 $1 到目标版本（当前：$("$BIN/$2" version 2>/dev/null | head -1)）…"; fi
  if $3; then return 0; fi
  if [ -x "$BIN/$2" ]; then warn "$1 目标版本下载失败，沿用现有版本继续安装"; return 0; fi
  err "$1 下载失败且无可用旧版本"; return 1
}
[ "$NEED_SB" = 1 ] && { fetch_kernel sing-box sb install_sb || exit 1; }
[ "$NEED_XR" = 1 ] && { fetch_kernel Xray xr install_xr || exit 1; }
[ "$NEED_CF" = 1 ] && { fetch_kernel cloudflared cf install_cf || exit 1; }

# ---------- 密钥材料（旧值优先保留） ----------
UUID_V="${uuid:-${OLD[uuid]:-}}"; [ -z "$UUID_V" ] && UUID_V=$(cat /proc/sys/kernel/random/uuid)
REYM_V="${reym:-apple.com}"
TLS_SNI="www.bing.com"
SHORT_ID="${OLD[short_id]:-}"; [ -z "$SHORT_ID" ] && SHORT_ID=$(openssl rand -hex 4)
[ ${#SHORT_ID} -ne 8 ] && SHORT_ID=$(openssl rand -hex 4)
SS_PASS="${OLD[ss_pass]:-}"; [ -z "$SS_PASS" ] && SS_PASS=$(openssl rand -base64 16 | tr -d '\n')
SOCK_USER="bigcat"; SOCK_PASS="${OLD[sock_pass]:-}"; [ -z "$SOCK_PASS" ] && SOCK_PASS=$(openssl rand -hex 9)

# Reality 密钥（xray 与 sing-box 各一对）
XR_PRIV="${OLD[xr_priv]:-}"; XR_PUB="${OLD[xr_pub]:-}"
if [ "$NEED_XR" = 1 ] && [ -z "$XR_PRIV" ]; then
  OUT=$("$BIN/xr" x25519 2>/dev/null)
  XR_PRIV=$(echo "$OUT" | grep -i 'private' | sed -E 's/.*: *//')
  XR_PUB=$(echo "$OUT" | grep -iE 'public|password' | sed -E 's/.*: *//')
fi
SB_PRIV="${OLD[sb_priv]:-}"; SB_PUB="${OLD[sb_pub]:-}"
if [ "$NEED_SB" = 1 ] && [ -z "$SB_PRIV" ]; then
  OUT=$("$BIN/sb" generate reality-keypair 2>/dev/null)
  SB_PRIV=$(echo "$OUT" | grep -i 'private' | sed -E 's/.*: *//')
  SB_PUB=$(echo "$OUT" | grep -i 'public' | sed -E 's/.*: *//')
fi
# VLESS 抗量子加密（enc 系列）
ENC_DEC="${OLD[enc_dec]:-}"; ENC_ENC="${OLD[enc_enc]:-}"
if [ "$NEED_XR" = 1 ] && [ -z "$ENC_DEC" ]; then
  OUT=$("$BIN/xr" vlessenc 2>/dev/null || true)
  ENC_DEC=$(echo "$OUT" | grep -i '"decryption"' | sed -E 's/.*: *"//; s/".*//')
  ENC_ENC=$(echo "$OUT" | grep -i '"encryption"' | sed -E 's/.*: *"//; s/".*//')
  [ -z "$ENC_DEC" ] && { ENC_DEC="none"; ENC_ENC="none"; warn "xray vlessenc 不可用，enc 协议回落为无加密 VLESS"; }
fi
# 自签证书
if [ ! -f "$CONF/cert.pem" ]; then
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -days 3650 -nodes \
    -keyout "$CONF/key.pem" -out "$CONF/cert.pem" -subj "/CN=$TLS_SNI" \
    -addext "subjectAltName=DNS:$TLS_SNI" >/dev/null 2>&1
fi

# ---------- 解析端口并写 plan.env ----------
SEL=""
for p in $PROTOS; do
  if [ -n "${!p+x}" ]; then
    SEL="$SEL $p"
    declare "PORT_$p=$(resolve_port $p "${OLD[port_$p]:-}")"
  fi
done
SUBPT_V=""; [ "${sub:-}" = "y" ] && SUBPT_V=$(resolve_port subpt "${OLD[subpt]:-}")
{
  echo "protos=${SEL# }"
  for p in $PROTOS; do v="PORT_$p"; [ -n "${!v:-}" ] && echo "port_$p=${!v}"; done
  echo "uuid=$UUID_V"; echo "reym=$REYM_V"; echo "tls_sni=$TLS_SNI"; echo "short_id=$SHORT_ID"
  echo "ss_pass=$SS_PASS"; echo "sock_user=$SOCK_USER"; echo "sock_pass=$SOCK_PASS"
  echo "xr_priv=$XR_PRIV"; echo "xr_pub=$XR_PUB"; echo "sb_priv=$SB_PRIV"; echo "sb_pub=$SB_PUB"
  echo "enc_dec=$ENC_DEC"; echo "enc_enc=$ENC_ENC"
  echo "ip=$IP_SHOW"; echo "ip4=$IP4"; echo "host=$HOST_SHOW"
  echo "name=${name:-}"; echo "cfip=${cfip:-}"; echo "cdnym=${cdnym:-}"
  echo "nodehost=${OLD[nodehost]:-$(hostname 2>/dev/null | tr -cd 'A-Za-z0-9._-' | cut -c1-60)}"
  echo "warp=${warp:-}"; echo "ippz=${ippz:-}"; echo "hyjpt=${hyjpt:-}"
  echo "sub=${sub:-}"; echo "subid=${subid:-$UUID_V}"; echo "subpt=$SUBPT_V"
  echo "argo=${argo:-}"; echo "agn=${agn:-}"; echo "agk=${agk:-}"
  echo "dir=$DIR"; echo "bin=$BIN"; echo "conf=$CONF"; echo "subd=$SUBD"
  echo "need_sb=$NEED_SB"; echo "need_xr=$NEED_XR"
} > "$PLAN"
chmod 600 "$PLAN" 2>/dev/null

# ---------- 配置/链接生成器 gen.py ----------
cat > "$DIR/gen.py" <<'PYEOF'
import base64, json, os
from urllib.parse import quote

def b64(s): return base64.b64encode(s.encode()).decode()
SB_WARP = {'1','2','3','7','8','9','10','11','12','13','14','15'}
XR_WARP = {'4','5','6','7','8','9','10','11','12','13','14','15'}
WARP_PRIV = '52cuYFgCJXp0LAq7+nWJIbCXXgU9eGggOc+Hlfz5u6A='
WARP_PUB = 'bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo='
WARP_V6 = '2606:4700:110:8d8d:1845:c39f:2dd5:a03a'
WARP_EP = 'engage.cloudflareclient.com'

def P(plan, k, d=''): return plan.get(k, d)
def has(plan, p): return p in P(plan, 'protos').split()
def port(plan, p): return int(P(plan, 'port_' + p, '0') or 0)
def prefix(plan): return P(plan, 'name') or 'BigCatA'

LABELS = {
    'vlpt': 'vl-reality-vision', 'xhpt': 'vl-xhttp-reality-enc', 'vxpt': 'vl-xhttp-enc',
    'vwpt': 'vl-ws-enc', 'xupt': 'vl-xhttp-tls-udp', 'xcpt': 'vl-xhttp-tls-tcpudp',
    'tupt': 'tuic', 'anpt': 'anytls', 'nvpt': 'naiveproxy', 'arpt': 'any-reality',
    'sspt': 'Shadowsocks-2022', 'hypt': 'hy2', 'vmpt': 'vm-ws', 'sopt': 'socks5',
}
ARGO_LABELS = {'vwpt': 'vl-ws-tls-argo', 'vmpt': 'vmess-ws-tls-argo'}
def dname(plan, p, variant=''):
    # 命名与 argosbx 界面一致：协议显示名-后缀（后缀=自定义 name 或服务器主机名）
    suffix = P(plan, 'name') or P(plan, 'nodehost') or P(plan, 'ip')
    if variant == 'argo':
        base = ARGO_LABELS.get(p, LABELS.get(p, p) + '-argo')
    else:
        base = LABELS.get(p, p)
        if variant: base += '-' + variant
    return f"{base}-{suffix}"

def links_for(plan, host=None, argo=False):
    u = P(plan, 'uuid'); host = host or P(plan, 'host'); ip = P(plan, 'ip')
    out = []
    def nm(p, variant=''): return dname(plan, p, 'argo' if argo else variant)
    if has(plan, 'vlpt'):
        out.append(f"vless://{u}@{host}:{port(plan,'vlpt')}?encryption=none&flow=xtls-rprx-vision&security=reality&sni={P(plan,'reym')}&fp=chrome&pbk={P(plan,'xr_pub')}&sid={P(plan,'short_id')}&type=tcp&headerType=none#{quote(nm('vlpt'))}")
    if has(plan, 'xhpt'):
        out.append(f"vless://{u}@{host}:{port(plan,'xhpt')}?encryption={quote(P(plan,'enc_enc'), safe='')}&security=reality&sni={P(plan,'reym')}&fp=chrome&pbk={P(plan,'xr_pub')}&sid={P(plan,'short_id')}&type=xhttp&path=%2Fbigcata-xh#{quote(nm('xhpt'))}")
    if has(plan, 'vxpt'):
        out.append(f"vless://{u}@{host}:{port(plan,'vxpt')}?encryption={quote(P(plan,'enc_enc'), safe='')}&security=none&type=xhttp&path=%2Fbigcata-vx#{quote(nm('vxpt'))}")
    if has(plan, 'vwpt'):
        if argo:
            out.append(f"vless://{u}@{host}:443?encryption={quote(P(plan,'enc_enc'), safe='')}&security=tls&sni={host}&type=ws&host={host}&path=%2Fbigcata-vw#{quote(nm('vwpt'))}")
        else:
            out.append(f"vless://{u}@{host}:{port(plan,'vwpt')}?encryption={quote(P(plan,'enc_enc'), safe='')}&security=none&type=ws&path=%2Fbigcata-vw#{quote(nm('vwpt'))}")
            cf = P(plan, 'cfip').split()
            if cf:
                out.append(f"vless://{u}@{cf[0]}:{port(plan,'vwpt')}?encryption={quote(P(plan,'enc_enc'), safe='')}&security=none&type=ws&host={P(plan,'cdnym') or ip}&path=%2Fbigcata-vw#{quote(nm('vwpt', 'CDN'))}")
    if has(plan, 'xupt'):
        out.append(f"vless://{u}@{host}:{port(plan,'xupt')}?encryption=none&security=tls&sni={P(plan,'tls_sni')}&alpn=h2&allowInsecure=1&type=xhttp&mode=auto&path=%2F#{quote(nm('xupt'))}")
    if has(plan, 'xcpt'):
        out.append(f"vless://{u}@{host}:{port(plan,'xcpt')}?encryption=none&security=tls&sni={P(plan,'tls_sni')}&alpn=h2&allowInsecure=1&type=xhttp&mode=auto&path=%2F#{quote(nm('xcpt'))}")
    if has(plan, 'tupt'):
        out.append(f"tuic://{u}:{u}@{host}:{port(plan,'tupt')}?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni={P(plan,'tls_sni')}&allow_insecure=1#{quote(nm('tupt'))}")
    if has(plan, 'anpt'):
        out.append(f"anytls://{u}@{host}:{port(plan,'anpt')}?insecure=1&sni={P(plan,'tls_sni')}#{quote(nm('anpt'))}")
    if has(plan, 'nvpt'):
        out.append(f"naive+https://{P(plan,'sock_user')}:{P(plan,'sock_pass')}@{host}:{port(plan,'nvpt')}#{quote(nm('nvpt'))}")
    if has(plan, 'arpt'):
        out.append(f"vless://{u}@{host}:{port(plan,'arpt')}?encryption=none&security=reality&sni={P(plan,'reym')}&fp=chrome&pbk={P(plan,'sb_pub')}&sid={P(plan,'short_id')}&type=tcp#{quote(nm('arpt'))}")
    if has(plan, 'sspt'):
        out.append(f"ss://{b64('2022-blake3-aes-128-gcm:' + P(plan,'ss_pass'))}@{host}:{port(plan,'sspt')}#{quote(nm('sspt'))}")
    if has(plan, 'hypt'):
        extra = ''
        if P(plan, 'hyjpt'):
            extra = '&mport=' + quote(P(plan, 'hyjpt').replace(' ', ','), safe='')
        out.append(f"hysteria2://{u}@{host}:{port(plan,'hypt')}?insecure=1&sni={P(plan,'tls_sni')}{extra}#{quote(nm('hypt'))}")
    if has(plan, 'vmpt'):
        vm = {"v": "2", "ps": nm('vmpt'), "add": host if argo else ip, "port": str(443 if argo else port(plan,'vmpt')),
              "id": u, "aid": "0", "scy": "auto", "net": "ws", "type": "none",
              "host": host if argo else "", "path": "/bigcata-vm", "tls": "tls" if argo else ""}
        out.append("vmess://" + b64(json.dumps(vm, ensure_ascii=False)))
        cf = P(plan, 'cfip').split()
        if cf and not argo:
            vm2 = dict(vm); vm2['ps'] = nm('vmpt', 'CDN'); vm2['add'] = cf[0]; vm2['host'] = P(plan, 'cdnym') or ip
            out.append("vmess://" + b64(json.dumps(vm2, ensure_ascii=False)))
    if has(plan, 'sopt'):
        out.append(f"socks://{b64(P(plan,'sock_user') + ':' + P(plan,'sock_pass'))}@{host}:{port(plan,'sopt')}#{quote(nm('sopt'))}")
    return out

def build_configs(plan):
    u = P(plan, 'uuid'); conf = P(plan, 'conf'); cert = conf + '/cert.pem'; key = conf + '/key.pem'
    warp = P(plan, 'warp')
    # ---- Xray ----
    if P(plan, 'need_xr') == '1':
        inb = []
        reality = {"target": P(plan, 'reym') + ":443", "serverNames": [P(plan, 'reym')],
                   "privateKey": P(plan, 'xr_priv'), "shortIds": [P(plan, 'short_id')]}
        if has(plan, 'vlpt'):
            inb.append({"port": port(plan,'vlpt'), "protocol": "vless", "tag": "vlpt",
                "settings": {"clients": [{"id": u, "flow": "xtls-rprx-vision"}], "decryption": "none"},
                "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": reality}, "sniffing": {"enabled": True}})
        if has(plan, 'xhpt'):
            inb.append({"port": port(plan,'xhpt'), "protocol": "vless", "tag": "xhpt",
                "settings": {"clients": [{"id": u}], "decryption": P(plan, 'enc_dec')},
                "streamSettings": {"network": "xhttp", "security": "reality", "realitySettings": reality,
                                   "xhttpSettings": {"path": "/bigcata-xh", "mode": "auto"}}, "sniffing": {"enabled": True}})
        if has(plan, 'vxpt'):
            inb.append({"port": port(plan,'vxpt'), "protocol": "vless", "tag": "vxpt",
                "settings": {"clients": [{"id": u}], "decryption": P(plan, 'enc_dec')},
                "streamSettings": {"network": "xhttp", "security": "none", "xhttpSettings": {"path": "/bigcata-vx", "mode": "auto"}}, "sniffing": {"enabled": True}})
        if has(plan, 'vwpt'):
            inb.append({"port": port(plan,'vwpt'), "protocol": "vless", "tag": "vwpt",
                "settings": {"clients": [{"id": u}], "decryption": P(plan, 'enc_dec')},
                "streamSettings": {"network": "ws", "security": "none", "wsSettings": {"path": "/bigcata-vw"}}, "sniffing": {"enabled": True}})
        tls_cert = [{"certificateFile": cert, "keyFile": key}]
        if has(plan, 'xupt'):
            inb.append({"port": port(plan,'xupt'), "protocol": "vless", "tag": "xupt",
                "settings": {"clients": [{"id": u}], "decryption": "none"},
                "streamSettings": {"network": "xhttp", "security": "tls", "tlsSettings": {"alpn": ["h2"], "certificates": tls_cert},
                                   "xhttpSettings": {"path": "/", "mode": "packet-up"}}, "sniffing": {"enabled": True}})
        if has(plan, 'xcpt'):
            inb.append({"port": port(plan,'xcpt'), "protocol": "vless", "tag": "xcpt",
                "settings": {"clients": [{"id": u}], "decryption": "none"},
                "streamSettings": {"network": "xhttp", "security": "tls", "tlsSettings": {"alpn": ["h2"], "certificates": tls_cert},
                                   "xhttpSettings": {"path": "/", "mode": "auto"}}, "sniffing": {"enabled": True}})
        if has(plan, 'vmpt'):
            inb.append({"port": port(plan,'vmpt'), "protocol": "vmess", "tag": "vmpt",
                "settings": {"clients": [{"id": u, "alterId": 0}]},
                "streamSettings": {"network": "ws", "security": "none", "wsSettings": {"path": "/bigcata-vm"}}, "sniffing": {"enabled": True}})
        if has(plan, 'sopt'):
            inb.append({"port": port(plan,'sopt'), "protocol": "socks", "tag": "sopt",
                "settings": {"auth": "password", "accounts": [{"user": P(plan,'sock_user'), "pass": P(plan,'sock_pass')}], "udp": True},
                "sniffing": {"enabled": True}})
        outb = [{"protocol": "freedom", "tag": "direct"}, {"protocol": "blackhole", "tag": "block"}]
        if warp in XR_WARP:
            wg = {"protocol": "wireguard", "tag": "warp",
                  "settings": {"secretKey": WARP_PRIV, "address": ["172.16.0.2/32", WARP_V6 + "/128"],
                               "peers": [{"publicKey": WARP_PUB, "endpoint": WARP_EP + ":2408"}], "noKernelTun": True}}
            outb = [wg] + outb
        xr = {"log": {"loglevel": "warning"}, "inbounds": inb, "outbounds": outb,
              "dns": {"servers": ["https+local://8.8.8.8/dns-query"]}}
        open(conf + '/xr.json', 'w').write(json.dumps(xr, indent=1))
    # ---- sing-box ----
    if P(plan, 'need_sb') == '1':
        inb = []
        tls_self = {"enabled": True, "certificate_path": cert, "key_path": key}
        if has(plan, 'tupt'):
            t = dict(tls_self); t['alpn'] = ['h3']
            inb.append({"type": "tuic", "tag": "tupt", "listen": "::", "listen_port": port(plan,'tupt'),
                        "users": [{"uuid": u, "password": u}], "congestion_control": "bbr", "tls": t})
        if has(plan, 'anpt'):
            inb.append({"type": "anytls", "tag": "anpt", "listen": "::", "listen_port": port(plan,'anpt'),
                        "users": [{"name": "bigcat", "password": u}], "tls": tls_self})
        if has(plan, 'nvpt'):
            inb.append({"type": "naive", "tag": "nvpt", "listen": "::", "listen_port": port(plan,'nvpt'),
                        "users": [{"username": P(plan,'sock_user'), "password": P(plan,'sock_pass')}], "tls": tls_self})
        if has(plan, 'arpt'):
            inb.append({"type": "vless", "tag": "arpt", "listen": "::", "listen_port": port(plan,'arpt'),
                        "users": [{"uuid": u}],
                        "tls": {"enabled": True, "server_name": P(plan, 'reym'),
                                "reality": {"enabled": True, "handshake": {"server": P(plan, 'reym'), "server_port": 443},
                                            "private_key": P(plan, 'sb_priv'), "short_id": [P(plan, 'short_id')]}}})
        if has(plan, 'sspt'):
            inb.append({"type": "shadowsocks", "tag": "sspt", "listen": "::", "listen_port": port(plan,'sspt'),
                        "method": "2022-blake3-aes-128-gcm", "password": P(plan, 'ss_pass')})
        if has(plan, 'hypt'):
            inb.append({"type": "hysteria2", "tag": "hypt", "listen": "::", "listen_port": port(plan,'hypt'),
                        "users": [{"password": u}], "tls": tls_self})
        sb = {"log": {"level": "warn"}, "dns": {"servers": [{"type": "https", "server": "8.8.8.8", "tag": "gg"}]},
              "inbounds": inb, "outbounds": [{"type": "direct", "tag": "direct"}], "route": {"final": "direct"}}
        if warp in SB_WARP:
            sb['endpoints'] = [{"type": "wireguard", "tag": "warp", "address": ["172.16.0.2/32", WARP_V6 + "/128"],
                                "private_key": WARP_PRIV,
                                "peers": [{"address": WARP_EP, "port": 2408, "public_key": WARP_PUB,
                                           "allowed_ips": ["0.0.0.0/0", "::/0"]}]}]
            sb['route'] = {"final": "warp"}
        open(conf + '/sb.json', 'w').write(json.dumps(sb, indent=1))
    # ---- 订阅文件 ----
    all_links = links_for(plan)
    dom = P(plan, 'ARGO_DOMAIN')
    if dom:
        main = P(plan, 'argo')
        if main in ('vwpt', 'vmpt'):
            all_links += links_for(plan, host=dom, argo=True)
    subdir = os.path.join(P(plan, 'subd'), P(plan, 'subid'))
    os.makedirs(subdir, exist_ok=True)
    open(os.path.join(subdir, 'jh.txt'), 'w').write(b64('\n'.join(all_links)))
    open(os.path.join(subdir, 'clmi.yaml'), 'w').write(clash_yaml(plan, dom))
    open(os.path.join(subdir, 'sbb.json'), 'w').write(sb_client_json(plan))

def clash_yaml(plan, dom=''):
    u = P(plan, 'uuid'); ip = P(plan, 'ip'); pre = prefix(plan); ps = []
    def add(d): ps.append(d)
    if has(plan, 'vlpt'): add({"name": dname(plan, 'vlpt'), "type": "vless", "server": ip, "port": port(plan,'vlpt'), "uuid": u, "flow": "xtls-rprx-vision", "network": "tcp", "tls": True, "udp": True, "servername": P(plan,'reym'), "reality-opts": {"public-key": P(plan,'xr_pub'), "short-id": P(plan,'short_id')}, "client-fingerprint": "chrome"})
    if has(plan, 'arpt'): add({"name": dname(plan, 'arpt'), "type": "vless", "server": ip, "port": port(plan,'arpt'), "uuid": u, "network": "tcp", "tls": True, "udp": True, "servername": P(plan,'reym'), "reality-opts": {"public-key": P(plan,'sb_pub'), "short-id": P(plan,'short_id')}, "client-fingerprint": "chrome"})
    if has(plan, 'hypt'): add({"name": dname(plan, 'hypt'), "type": "hysteria2", "server": ip, "port": port(plan,'hypt'), "password": u, "sni": P(plan,'tls_sni'), "skip-cert-verify": True})
    if has(plan, 'tupt'): add({"name": dname(plan, 'tupt'), "type": "tuic", "server": ip, "port": port(plan,'tupt'), "uuid": u, "password": u, "congestion-controller": "bbr", "alpn": ["h3"], "skip-cert-verify": True})
    if has(plan, 'sspt'): add({"name": dname(plan, 'sspt'), "type": "ss", "server": ip, "port": port(plan,'sspt'), "cipher": "2022-blake3-aes-128-gcm", "password": P(plan,'ss_pass'), "udp": True})
    if has(plan, 'vmpt'): add({"name": dname(plan, 'vmpt'), "type": "vmess", "server": ip, "port": port(plan,'vmpt'), "uuid": u, "alterId": 0, "cipher": "auto", "network": "ws", "ws-opts": {"path": "/bigcata-vm"}, "udp": True})
    if has(plan, 'vwpt'): add({"name": dname(plan, 'vwpt'), "type": "vless", "server": ip, "port": port(plan,'vwpt'), "uuid": u, "network": "ws", "ws-opts": {"path": "/bigcata-vw"}, "udp": True})
    if has(plan, 'anpt'): add({"name": dname(plan, 'anpt'), "type": "anytls", "server": ip, "port": port(plan,'anpt'), "password": u, "sni": P(plan,'tls_sni'), "skip-cert-verify": True, "udp": True})
    if has(plan, 'sopt'): add({"name": dname(plan, 'sopt'), "type": "socks5", "server": ip, "port": port(plan,'sopt'), "username": P(plan,'sock_user'), "password": P(plan,'sock_pass'), "udp": True})
    names = [p['name'] for p in ps]
    def yesc(s): return json.dumps(str(s), ensure_ascii=False)
    lines = ["proxies:"]
    for p in ps:
        lines.append("  - " + json.dumps(p, ensure_ascii=False))
    lines.append("proxy-groups:")
    lines.append('  - {name: BigCatA, type: select, proxies: ' + json.dumps(names + ['DIRECT'], ensure_ascii=False) + '}')
    lines.append("rules:")
    lines.append("  - MATCH,BigCatA")
    return '\n'.join(lines) + '\n'

def sb_client_json(plan):
    u = P(plan, 'uuid'); ip = P(plan, 'ip'); pre = prefix(plan); outs = []
    if has(plan, 'vlpt'): outs.append({"type": "vless", "tag": dname(plan, 'vlpt'), "server": ip, "server_port": port(plan,'vlpt'), "uuid": u, "flow": "xtls-rprx-vision", "tls": {"enabled": True, "server_name": P(plan,'reym'), "utls": {"enabled": True, "fingerprint": "chrome"}, "reality": {"enabled": True, "public_key": P(plan,'xr_pub'), "short_id": P(plan,'short_id')}}})
    if has(plan, 'hypt'): outs.append({"type": "hysteria2", "tag": dname(plan, 'hypt'), "server": ip, "server_port": port(plan,'hypt'), "password": u, "tls": {"enabled": True, "server_name": P(plan,'tls_sni'), "insecure": True}})
    if has(plan, 'tupt'): outs.append({"type": "tuic", "tag": dname(plan, 'tupt'), "server": ip, "server_port": port(plan,'tupt'), "uuid": u, "password": u, "congestion_control": "bbr", "tls": {"enabled": True, "alpn": ["h3"], "insecure": True}})
    if has(plan, 'sspt'): outs.append({"type": "shadowsocks", "tag": dname(plan, 'sspt'), "server": ip, "server_port": port(plan,'sspt'), "method": "2022-blake3-aes-128-gcm", "password": P(plan,'ss_pass')})
    if has(plan, 'anpt'): outs.append({"type": "anytls", "tag": dname(plan, 'anpt'), "server": ip, "server_port": port(plan,'anpt'), "password": u, "tls": {"enabled": True, "server_name": P(plan,'tls_sni'), "insecure": True}})
    tags = [o['tag'] for o in outs]
    full = {"outbounds": [{"type": "selector", "tag": "proxy", "outbounds": tags + ["direct"], "default": tags[0] if tags else "direct"}] + outs + [{"type": "direct", "tag": "direct"}],
            "route": {"final": "proxy"}, "inbounds": [{"type": "mixed", "listen": "127.0.0.1", "listen_port": 2080}]}
    return json.dumps(full, indent=1)

def print_links(plan):
    ls = links_for(plan)
    for l in ls: print(l)
    dom = P(plan, 'ARGO_DOMAIN')
    if dom and P(plan, 'argo') in ('vwpt', 'vmpt'):
        print("\n--- Argo 隧道节点（域名 " + dom + "）---")
        for l in links_for(plan, host=dom, argo=True): print(l)
    if P(plan, 'sub') == 'y' and P(plan, 'subpt'):
        base = f"http://{P(plan,'host')}:{P(plan,'subpt')}/{P(plan,'subid')}"
        print("\n--- 订阅链接 ---")
        print("聚合订阅: " + base + "/jh.txt")
        print("Clash/Mihomo: " + base + "/clmi.yaml")
        print("Sing-box: " + base + "/sbb.json")
    print("\n管理：bigcata list 显示节点 | bigcata rep 重置 | bigcata res 重启 | bigcata del 卸载")
PYEOF

# ---------- 生成配置并校验 ----------
PLAN_PATH="$PLAN" python3 - <<'PYEOF'
import os
plan = {}
for line in open(os.environ['PLAN_PATH'], encoding='utf-8'):
    line = line.rstrip('\n')
    if '=' in line:
        k, v = line.split('=', 1); plan[k] = v
plan['ARGO_DOMAIN'] = ''
exec(open(os.path.join(plan['dir'], 'gen.py'), encoding='utf-8').read())
build_configs(plan)
print("配置已生成")
PYEOF
[ "$NEED_XR" = 1 ] && { "$BIN/xr" run -test -config "$CONF/xr.json" >/dev/null 2>&1 || { err "Xray 配置校验失败：$BIN/xr run -test -config $CONF/xr.json"; exit 1; }; }
[ "$NEED_SB" = 1 ] && { "$BIN/sb" check -c "$CONF/sb.json" >/dev/null 2>&1 || { err "sing-box 配置校验失败：$BIN/sb check -c $CONF/sb.json"; exit 1; }; }
say "配置校验通过。"

# ---------- 启动内核 ----------
if [ "$NEED_XR" = 1 ]; then svc_write xr "$BIN/xr run -c $CONF/xr.json"; svc_start xr "$BIN/xr run -c $CONF/xr.json"; fi
if [ "$NEED_SB" = 1 ]; then svc_write sb "$BIN/sb run -c $CONF/sb.json"; svc_start sb "$BIN/sb run -c $CONF/sb.json"; fi

# ---------- Argo 隧道 ----------
rm -f "$DIR/argo-domain.txt"
if [ -n "${argo:-}" ]; then
  AP="PORT_$argo"; APORT="${!AP:-}"
  if [ -n "${agn:-}" ] && [ -n "${agk:-}" ]; then
    echo "$agn" > "$DIR/argo-domain.txt"
    svc_write argo "$BIN/cf tunnel --no-autoupdate run --token $agk"
    svc_start argo "$BIN/cf tunnel --no-autoupdate run --token $agk"
    say "Argo 固定隧道已启动：$agn"
  elif [ -n "$APORT" ]; then
    svc_write argo "$BIN/cf tunnel --no-autoupdate --url http://127.0.0.1:$APORT"
    if [ "$HAS_SYSTEMD" = 1 ]; then sudo systemctl restart bigcata-argo; else nohup "$BIN/cf" tunnel --no-autoupdate --url "http://127.0.0.1:$APORT" >"$DIR/argo.log" 2>&1 & fi
    say "Argo 临时隧道启动中，等待域名…"
    for i in $(seq 1 40); do
      sleep 1
      D=$( (sudo journalctl -u bigcata-argo --no-pager -n 60 2>/dev/null; cat "$DIR/argo.log" 2>/dev/null) | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1 | sed 's|https://||')
      [ -n "$D" ] && { echo "$D" > "$DIR/argo-domain.txt"; say "Argo 临时域名：$D"; break; }
    done
    [ -f "$DIR/argo-domain.txt" ] || warn "Argo 域名获取超时，稍后运行 bigcata list 查看日志 $DIR/argo.log"
  fi
fi

# ---------- 订阅服务 ----------
if [ "${sub:-}" = "y" ] && [ -n "$SUBPT_V" ]; then
  PY3=$(command -v python3)
  svc_write sub "$PY3 -m http.server $SUBPT_V --bind 0.0.0.0 --directory $SUBD"
  svc_start sub "$PY3 -m http.server $SUBPT_V --bind 0.0.0.0 --directory $SUBD"
fi

# ---------- HY2 端口跳跃 / 开放端口 ----------
if [ -n "${hyjpt:-}" ] && [ -n "${PORT_hypt:-}" ] && have iptables; then
  sudo iptables -t nat -N BIGCATA_HOP 2>/dev/null; sudo iptables -t nat -F BIGCATA_HOP
  sudo iptables -t nat -C PREROUTING -j BIGCATA_HOP 2>/dev/null || sudo iptables -t nat -A PREROUTING -j BIGCATA_HOP
  for spec in $hyjpt; do
    sudo iptables -t nat -A BIGCATA_HOP -p udp --dport "$spec" -j REDIRECT --to-port "$PORT_hypt" 2>/dev/null
  done
  say "HY2 端口跳跃已设置：$hyjpt -> $PORT_hypt"
fi
if [ "${oap:-}" = "y" ]; then
  warn "oap：开放当前系统所有端口（iptables INPUT ACCEPT + ufw 关闭）"
  have ufw && sudo ufw --force disable >/dev/null 2>&1
  have iptables && { sudo iptables -P INPUT ACCEPT 2>/dev/null; sudo iptables -F INPUT 2>/dev/null; }
fi
[ -n "${warp:-}" ] && say "WARP 出站模式 warp=$warp 已按内核启用（sing-box 1/2/3/7-15，xray 4-15）"

# ---------- 快捷命令 bigcata ----------
if [ -f "$0" ] && [ "$0" != "$DIR/bigcata.sh" ]; then cp "$0" "$DIR/bigcata.sh" 2>/dev/null; fi
[ -f "$DIR/bigcata.sh" ] || dl "$URL_RAW" "$DIR/bigcata.sh" 2>/dev/null
if [ -f "$DIR/bigcata.sh" ]; then
  chmod +x "$DIR/bigcata.sh"
  printf '#!/bin/bash\nexec bash "%s/bigcata.sh" "$@"\n' "$DIR" > /tmp/bigcata-cmd
  if [ "$(id -u)" = 0 ]; then cp /tmp/bigcata-cmd /usr/local/bin/bigcata && chmod +x /usr/local/bin/bigcata;
  else mkdir -p "$HOME/.local/bin" && cp /tmp/bigcata-cmd "$HOME/.local/bin/bigcata" && chmod +x "$HOME/.local/bin/bigcata"; fi
fi

sleep 2
say "✅ BigCat A v$VER 安装完成，节点信息："
echo "----------------------------------------------------------------"
bash "$DIR/bigcata.sh" list 2>/dev/null || PLAN_PATH="$PLAN" python3 -c "
import os
plan={}
for line in open(os.environ['PLAN_PATH'], encoding='utf-8'):
    line=line.rstrip('\n')
    if '=' in line:
        k,v=line.split('=',1); plan[k]=v
f=os.path.join(plan['dir'],'argo-domain.txt')
plan['ARGO_DOMAIN']=open(f).read().strip() if os.path.exists(f) else ''
exec(open(os.path.join(plan['dir'],'gen.py'), encoding='utf-8').read())
print_links(plan)"
echo "----------------------------------------------------------------"
