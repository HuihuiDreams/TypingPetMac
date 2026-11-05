'use strict';
const $ = id => document.getElementById(id);
let csrf = '', page = 1, selected = null, busy = false, revisionRequest = 0;
const el = (tag, text, className) => { const n = document.createElement(tag); if (text !== undefined) n.textContent = text; if(className) n.className = className; return n; };
async function api(path, options={}) {
  const response = await fetch('/api/'+path, {credentials:'same-origin',...options,headers:{'X-Admin-CSRF':csrf,...options.headers}});
  if (!response.ok) throw new Error('요청 실패 ('+response.status+')');
  return response.json();
}
async function load(reset=true) {
  if(busy) return; busy=true; $('refresh').disabled=true;
  try {
    if(reset){page=1;$('packs').replaceChildren();}
    $('status').textContent='팩 목록을 불러오는 중…';
    const result=await api('packs?page='+page);
    for(const pack of result.packs) {
      const card=el('button',undefined,'pack');card.type='button';
      card.append(el('span',pack.isPublic?'커뮤니티 공개':'코드 공유','badge'),el('h2',pack.name),el('span',(pack.code||'코드 없음')+' · v'+pack.version+' · 이미지 '+pack.presetCount+'개','meta'),el('p',pack.creatorMessage));
      card.addEventListener('click',()=>openPack(pack));$('packs').append(card);
    }
    page=result.nextPage;$('more').hidden=!page;
    $('status').textContent=$('packs').children.length?$('packs').children.length+'개 팩을 표시하고 있습니다.':'배포 중인 팩이 없습니다.';
  }catch(error){$('status').textContent=error.message;}finally{busy=false;$('refresh').disabled=false;}
}
async function openPack(pack) {
  selected=pack;$('title').textContent=pack.name;$('versions').replaceChildren();$('images').replaceChildren();$('mappings').replaceChildren();$('description').textContent='불러오는 중…';$('detail').showModal();
  try {
    const result=await api('packs/'+pack.id+'/versions');if(selected!==pack)return;
    for(const version of result.versions){const option=el('option','v'+version.version+' · '+new Date(version.publishedAt*1000).toLocaleString());option.value=version.version;$('versions').append(option);}
    await showVersion();
  }catch(error){$('description').textContent=error.message;}
}
function keyName(code){return ({0:'A',1:'S',2:'D',3:'F',4:'H',5:'G',6:'Z',7:'X',8:'C',9:'V',11:'B',12:'Q',13:'W',14:'E',15:'R',16:'Y',17:'T',31:'O',32:'U',34:'I',35:'P',36:'Enter',37:'L',38:'J',40:'K',45:'N',46:'M',47:'.',48:'Tab',49:'Space',51:'Delete',53:'Esc',123:'←',124:'→',125:'↓',126:'↑'})[code]||'Key '+code;}
async function showVersion(){
 const ticket=++revisionRequest,pack=selected,version=$('versions').value;if(!pack||!version)return;
 try{
  const result=await api('packs/'+pack.id+'/versions/'+version);if(ticket!==revisionRequest||pack!==selected)return;
  const manifest=result.manifest,config=manifest.configuration,names=new Map(config.presets.map(p=>[p.id,p.name]));
  $('description').textContent=manifest.creatorMessage||'';$('images').replaceChildren();$('mappings').replaceChildren();
  for(const preset of config.presets){const card=el('div',undefined,'image-card'),image=document.createElement('img');image.alt=preset.name;image.loading='lazy';image.src='/api/packs/'+pack.id+'/versions/'+version+'/images/'+encodeURIComponent(preset.id);card.append(image,el('span',preset.name));$('images').append(card);}
  const selection=s=>(s.presetIDs||[]).map(id=>names.get(id)||id).join(', ')+' ('+(s.mode==='random'?'랜덤':'순서대로')+')';
  $('defaults').textContent='쉬고 있을 때: '+selection(config.idle)+' / 일반 타이핑: '+selection(config.unassigned);
  for(const mapping of config.mappings||[]){const bits=typeof mapping.stroke.modifiers==='number'?mapping.stroke.modifiers:mapping.stroke.modifiers.rawValue;const label=(bits&4?'⌃':'')+(bits&2?'⌥':'')+(bits&8?'⇧':'')+(bits&1?'⌘':'')+keyName(mapping.stroke.keyCode);const row=el('div',undefined,'mapping');row.append(el('strong',label),el('span',selection(mapping.selection)));$('mappings').append(row);}
  if(!config.mappings?.length)$('mappings').append(el('p','개별 키 배치 없음 — 일반 타이핑 구성을 사용합니다.'));
 }catch(error){if(ticket===revisionRequest)$('description').textContent=error.message;}
}
$('refresh').addEventListener('click',()=>load(true));$('more').addEventListener('click',()=>load(false));$('close').addEventListener('click',()=>{$('detail').close();selected=null;revisionRequest++;});$('versions').addEventListener('change',showVersion);
$('delete').addEventListener('click',async()=>{const pack=selected;if(!pack||!confirm('“'+pack.name+'” 팩을 삭제할까요?\n공개 목록과 새 다운로드가 중단됩니다. 이미 받은 로컬 사본은 유지됩니다.'))return;$('delete').disabled=true;try{await api('packs/'+pack.id,{method:'DELETE'});$('detail').close();selected=null;await load(true);}catch(error){$('description').textContent=error.message;}finally{$('delete').disabled=false;}});
(async()=>{try{const session=await api('session');csrf=session.csrfToken;$('user').textContent=session.username;await load();}catch(error){$('status').textContent=error.message;}})();
