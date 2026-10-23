
const $ = id => document.getElementById(id);
const state = { deposits:0, idle:0, deployed:0, shares:0, fees:0, harvested:0 };
function log(m){ const el=$('log'); const t=new Date().toLocaleTimeString(); el.textContent=`[${t}] ${m}\n`+el.textContent.slice(0,2000); }
function render(){
  const nav = state.idle+state.deployed;
  $('kpis').innerHTML = [
    ['NAV', nav.toLocaleString()],
    ['Idle', state.idle.toLocaleString()],
    ['Deployed', state.deployed.toLocaleString()],
    ['Fees minted', state.fees.toLocaleString()],
  ].map(([l,v])=>`<div class="kpi"><div class="l">${l}</div><div class="v">${v}</div></div>`).join('');
}
$('actions').innerHTML = `
<button class="btn primary" id="dep">Deposit</button>
<button class="btn ghost" id="al">Allocate</button>
<button class="btn ghost" id="hv">Harvest 1%</button>
<button class="btn ghost" id="wd">Withdraw 25%</button>`;
$('dep').onclick=()=>{ const a=+($('amt').value||0); state.deposits+=a; state.idle+=a; state.shares+=a; log(`deposit ${a} → mint shares`); render(); };
$('al').onclick=()=>{ const pct=+($('alloc').value||0)/100; const move=Math.floor(state.idle*pct); state.idle-=move; state.deployed+=move; log(`allocate ${move} to strategy`); render(); };
$('hv').onclick=()=>{ const profit=Math.floor(state.deployed*0.01); const fee=Math.floor(profit*0.10); state.deployed+=profit; state.fees+=fee; state.harvested+=profit; log(`harvest profit=${profit} feeShares=${fee}`); render(); };
$('wd').onclick=()=>{ const nav=state.idle+state.deployed; const out=Math.floor(nav*0.25); let left=out; if(left>state.idle){ const need=left-state.idle; state.deployed-=need; state.idle+=need; } state.idle-=left; log(`withdraw ${out} (pull from strategy if needed)`); render(); };
render(); log('VaultForge demo ready — simulated ERC-4626 flows');
