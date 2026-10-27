// BigCat A 生成器交互测试（jsdom）：node tests/test_generator.mjs
import { readFileSync } from 'fs';
import { JSDOM } from '/tmp/domtest/node_modules/jsdom/lib/api.js';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf-8');
const dom = new JSDOM(html, { url: 'http://localhost/', runScripts: 'dangerously', pretendToBeVisual: true });
const { document } = dom.window;
const out = () => document.getElementById('output').value;
const fire = (el, type='change') => el.dispatchEvent(new dom.window.Event(type, { bubbles: true }));
let fails = 0;
const eq = (name, got, want) => {
  const ok = got === want;
  if (!ok) fails++;
  console.log((ok ? 'PASS' : 'FAIL') + ' | ' + name + '\n  got : ' + got + (ok ? '' : '\n  want: ' + want));
};
const BASE = 'bash <(curl -Ls https://raw.githubusercontent.com/zhanghaobo1987/BigCat-A/main/bigcata.sh)';

eq('初始输出', out(), BASE);

// 预设：极简直连
document.querySelector('[data-preset="simple"]').click();
eq('预设极简', out(), 'vlpt=443 hypt=8443 ' + BASE);

// 勾 Tuic 2053 + 开订阅
const tupt = document.querySelector('[data-proto="tupt"]');
tupt.checked = true; fire(tupt);
const tport = document.querySelector('[data-port="tupt"]');
tport.value = '2053'; fire(tport, 'input');
const sub = document.getElementById('sub'); sub.value = 'y'; fire(sub);
eq('加Tuic+订阅', out(), 'vlpt=443 tupt=2053 hypt=8443 sub=y ' + BASE);

// 粘回命令解析
const o = document.getElementById('output');
o.value = 'vlpt="443" hypt="8443" uuid="11111111-2222-3333-4444-555555555555" ' + BASE;
fire(o, 'input');
eq('解析后vlpt勾选', document.querySelector('[data-proto="vlpt"]').checked, true);
eq('解析后tupt取消', document.querySelector('[data-proto="tupt"]').checked, false);
eq('解析后uuid', document.getElementById('uuid').value, '11111111-2222-3333-4444-555555555555');
eq('解析后输出', out(), 'vlpt=443 hypt=8443 uuid=11111111-2222-3333-4444-555555555555 ' + BASE);

// list 快捷命令（ippz 为空）
document.querySelector('[data-cmd="list"]').click();
eq('list命令', out(), BASE + ' list');

// alns 联动：未开时 nvpt 禁用，开后可选
eq('nvpt默认禁用', document.querySelector('[data-proto="nvpt"]').disabled, true);
const alns = document.getElementById('alns'); alns.value = 'y'; fire(alns);
eq('alns开启后nvpt可选', document.querySelector('[data-proto="nvpt"]').disabled, false);

// 端口重复提醒
document.getElementById('resetBtn').click();
const vl = document.querySelector('[data-proto="vlpt"]'); vl.checked = true; fire(vl);
document.querySelector('[data-port="vlpt"]').value = '443'; fire(document.querySelector('[data-port="vlpt"]'), 'input');
const xh = document.querySelector('[data-proto="xhpt"]'); xh.checked = true; fire(xh);
document.querySelector('[data-port="xhpt"]').value = '443'; fire(document.querySelector('[data-port="xhpt"]'), 'input');
eq('重复端口提醒', document.getElementById('msg').textContent.includes('443'), true);

console.log(fails === 0 ? '\nALL PASS' : '\n' + fails + ' FAILED');
process.exit(fails ? 1 : 0);
