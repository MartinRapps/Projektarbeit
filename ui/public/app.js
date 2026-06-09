const API = '';
let allSteps = [];
let selectedStepId = null;
let allScripts = [];
let selectedScriptId = null;
let scriptSessionId = null;
let scriptEventSource = null;

function $(sel) { return document.querySelector(sel); }
function $$(sel) { return document.querySelectorAll(sel); }

function fmtSize(bytes) {
  if (!bytes) return '';
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1048576) return (bytes/1024).toFixed(1) + ' KB';
  return (bytes/1048576).toFixed(1) + ' MB';
}

function fmtTime(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  return d.toLocaleString('de-DE', {day:'2-digit', month:'2-digit', hour:'2-digit', minute:'2-digit'});
}

// == Load All Data ==
async function loadAll() {
  try {
    const [stepsRes, scriptsRes] = await Promise.all([
      fetch('/api/steps'),
      fetch('/api/scripts')
    ]);
    allSteps = await stepsRes.json();
    allScripts = await scriptsRes.json();
    renderStepList();
    renderFlowchart();
    renderScriptList();
    updateFooter();
    if (selectedStepId) {
      const idx = allSteps.findIndex(s => s.id === selectedStepId);
      if (idx >= 0) selectStep(idx);
      else { selectedStepId = null; selectStep(0); }
    } else {
      selectStep(0);
    }
  } catch (e) {
    $('#footer-info').textContent = 'Fehler beim Laden der Daten: ' + e.message;
  }
}

// == Left Panel: Step List ==
const STEP_ICONS = ['🎬','🖼️','🎭','📐','🧊','🔗','📏','🌍','📊'];

function renderStepList() {
  const list = $('#step-list');
  list.innerHTML = '';
  const completed = allSteps.filter(s => s.nonempty).length;
  $('#step-count').textContent = completed + '/' + allSteps.length;

  allSteps.forEach((step, i) => {
    const el = document.createElement('div');
    el.className = 'step-item' +
      (step.nonempty ? ' completed' : step.exists ? ' partial' : ' empty') +
      (step.id === selectedStepId ? ' active' : '');
    el.dataset.index = i;
    el.innerHTML = `
      <span class="step-indicator"></span>
      <span class="step-icon">${STEP_ICONS[i] || '📋'}</span>
      <div class="step-info">
        <div class="step-label">${step.label}</div>
        <div class="step-meta">
          <span class="step-container">${step.container}</span>
          <span class="step-files">${step.file_count} Dateien</span>
        </div>
      </div>`;
    el.addEventListener('click', () => { selectStep(i); });
    list.appendChild(el);
  });
}

function selectStep(index) {
  const step = allSteps[index];
  if (!step) return;
  selectedStepId = step.id;
  $$('.step-item').forEach((el, i) => {
    el.classList.toggle('active', i === index);
  });
  updateFlowchartActive(step.id);
  renderPreview(step);
}

// == Center Panel: Flowchart ==
function renderFlowchart() {
  const svg = $('#flowchart');
  const W = 700, H = 1060;
  svg.setAttribute('viewBox', `0 0 ${W} ${H}`);

  const defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');
  defs.innerHTML = `
    <linearGradient id="g-active" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stop-color="#7c5cfc"/>
      <stop offset="100%" stop-color="#a78bfa"/>
    </linearGradient>
    <linearGradient id="g-done" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stop-color="#34d399"/>
      <stop offset="100%" stop-color="#6ee7b7"/>
    </linearGradient>
    <filter id="glow-active">
      <feGaussianBlur stdDeviation="3" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto">
      <path d="M0,0 L10,5 L0,10 Z" fill="#3a3d52"/>
    </marker>
    <marker id="arrow-active" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto">
      <path d="M0,0 L10,5 L0,10 Z" fill="#7c5cfc"/>
    </marker>`;
  svg.innerHTML = '';
  svg.appendChild(defs);

  const nodes = [
    { id:'raw', x:350, y:40, w:240, h:44, label:'Drohnen-Video + GNSS', sub:'60 FPS RAW + Referenzmessung', color:'#60a5fa', icon:'🎬' },
    { id:'decision', x:350, y:130, w:180, h:44, label:'Kabel sichtbar?', sub:'', color:'#fbbf24', diamond:true },
    { id:'pathA', x:160, y:210, w:200, h:44, label:'SAM 3 Video Predictor', sub:'Temporales Tracking', color:'#7c5cfc' },
    { id:'pathB', x:540, y:210, w:200, h:44, label:'SAHI + SAM 3 Image', sub:'Fallback', color:'#f87171' },
    { id:'extractA', x:160, y:300, w:200, h:44, label:'Frame-Extraktion', sub:'6 FPS Masken + Bilder', color:'#7c5cfc' },
    { id:'extractB', x:540, y:300, w:200, h:44, label:'Maskengenerierung', sub:'6 FPS Masken', color:'#f87171' },
    { id:'colmap', x:350, y:390, w:240, h:44, label:'COLMAP SfM', sub:'Sparse Punktwolke + Posen', color:'#fb923c' },
    { id:'cc', x:560, y:480, w:190, h:44, label:'CloudCompare (Host)', sub:'GCP Point Picking', color:'#ef4444' },
    { id:'sts', x:140, y:480, w:200, h:44, label:'Segment-then-Splat', sub:'Object-specific 3DGS', color:'#06b6d4' },
    { id:'sugar', x:240, y:570, w:220, h:44, label:'SuGaR Meshing', sub:'Poisson Reconstruction', color:'#a855f7' },
    { id:'dgtal', x:240, y:660, w:220, h:44, label:'DGtal Centerline', sub:'Kabel-Sub-Mesh -> 1D-Kurve', color:'#14b8a6' },
    { id:'final', x:350, y:750, w:240, h:44, label:'GDAL Georeferenzierung', sub:'UTM-Transformation', color:'#14b8a6' },
    { id:'eval', x:350, y:840, w:240, h:44, label:'Wissenschaftliche Evaluation', sub:'RMSE + Hausdorff', color:'#34d399' },
  ];

  const edges = [
    { from:'raw', to:'decision' },
    { from:'decision', to:'pathA' },
    { from:'decision', to:'pathB' },
    { from:'pathA', to:'extractA' },
    { from:'pathB', to:'extractB' },
    { from:'extractA', to:'colmap' },
    { from:'extractB', to:'colmap' },
    { from:'colmap', to:'sts' },
    { from:'colmap', to:'cc' },
    { from:'sts', to:'sugar' },
    { from:'sugar', to:'dgtal' },
    { from:'dgtal', to:'final' },
    { from:'cc', to:'final' },
    { from:'final', to:'eval' },
  ];

  svg._nodes = nodes;
  svg._edges = edges;

  edges.forEach(e => {
    const from = nodes.find(n => n.id === e.from);
    const to = nodes.find(n => n.id === e.to);
    if (!from || !to) return;
    const line = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    const d = routeEdge(from, to);
    line.setAttribute('d', d);
    line.setAttribute('fill', 'none');
    line.setAttribute('stroke', '#3a3d52');
    line.setAttribute('stroke-width', '2');
    line.setAttribute('marker-end', 'url(#arrow)');
    line.dataset.from = e.from;
    line.dataset.to = e.to;
    line.classList.add('flow-edge');
    svg.appendChild(line);
  });

  nodes.forEach(n => {
    const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
    g.dataset.id = n.id;
    g.classList.add('flow-node');

    if (n.diamond) {
      const poly = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
      const pts = `${n.x},${n.y-30} ${n.x+90},${n.y} ${n.x},${n.y+30} ${n.x-90},${n.y}`;
      poly.setAttribute('points', pts);
      poly.setAttribute('fill', 'rgba(251,191,36,0.08)');
      poly.setAttribute('stroke', '#fbbf24');
      poly.setAttribute('stroke-width', '2');
      g.appendChild(poly);
    } else {
      const rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
      rect.setAttribute('x', n.x - n.w/2);
      rect.setAttribute('y', n.y - n.h/2);
      rect.setAttribute('width', n.w);
      rect.setAttribute('height', n.h);
      rect.setAttribute('rx', '8');
      rect.setAttribute('fill', n.color + '15');
      rect.setAttribute('stroke', n.color);
      rect.setAttribute('stroke-width', '1.5');
      rect.classList.add('node-rect');
      g.appendChild(rect);
    }

    const title = document.createElementNS('http://www.w3.org/2000/svg', 'text');
    title.setAttribute('x', n.x);
    title.setAttribute('y', n.diamond ? n.y - 4 : n.y - 5);
    title.setAttribute('text-anchor', 'middle');
    title.setAttribute('fill', '#e2e4f0');
    title.setAttribute('font-size', '12');
    title.setAttribute('font-weight', '600');
    title.textContent = n.icon ? n.icon + ' ' + n.label : n.label;
    g.appendChild(title);

    if (n.sub) {
      const sub = document.createElementNS('http://www.w3.org/2000/svg', 'text');
      sub.setAttribute('x', n.x);
      sub.setAttribute('y', n.diamond ? n.y + 12 : n.y + 14);
      sub.setAttribute('text-anchor', 'middle');
      sub.setAttribute('fill', '#8b8fa3');
      sub.setAttribute('font-size', '9');
      sub.textContent = n.sub;
      g.appendChild(sub);
    }

    g.style.cursor = 'pointer';
    g.addEventListener('click', () => {
      const idx = allSteps.findIndex(s => s.id === n.id);
      if (idx >= 0) selectStep(idx);
    });

    svg.appendChild(g);
  });

  const legendY = 930;
  const containers = [
    { label:'Container A (SAM 3)', color:'#7c5cfc', x:80 },
    { label:'Container B (COLMAP)', color:'#fb923c', x:260 },
    { label:'Host (manuell)', color:'#ef4444', x:440 },
    { label:'Container C (STS)', color:'#06b6d4', x:600 },
  ];
  containers.forEach(c => {
    const cx = c.x;
    const rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
    rect.setAttribute('x', cx);
    rect.setAttribute('y', legendY);
    rect.setAttribute('width', '10');
    rect.setAttribute('height', '10');
    rect.setAttribute('rx', '2');
    rect.setAttribute('fill', c.color);
    svg.appendChild(rect);
    const txt = document.createElementNS('http://www.w3.org/2000/svg', 'text');
    txt.setAttribute('x', cx + 16);
    txt.setAttribute('y', legendY + 9);
    txt.setAttribute('fill', '#8b8fa3');
    txt.setAttribute('font-size', '10');
    txt.textContent = c.label;
    svg.appendChild(txt);
  });

  const cont2 = [
    { label:'Container D (SuGaR)', color:'#a855f7', x:80 },
    { label:'Container E (DGtal/GDAL)', color:'#14b8a6', x:260 },
    { label:'Evaluation', color:'#34d399', x:440 },
  ];
  cont2.forEach(c => {
    const cx = c.x;
    const rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
    rect.setAttribute('x', cx);
    rect.setAttribute('y', legendY + 22);
    rect.setAttribute('width', '10');
    rect.setAttribute('height', '10');
    rect.setAttribute('rx', '2');
    rect.setAttribute('fill', c.color);
    svg.appendChild(rect);
    const txt = document.createElementNS('http://www.w3.org/2000/svg', 'text');
    txt.setAttribute('x', cx + 16);
    txt.setAttribute('y', legendY + 31);
    txt.setAttribute('fill', '#8b8fa3');
    txt.setAttribute('font-size', '10');
    txt.textContent = c.label;
    svg.appendChild(txt);
  });
}

function routeEdge(from, to) {
  const dy = to.y - from.y;
  const dx = to.x - from.x;
  const yOff = from.h ? (from.h/2 + 6) : 20;
  const yOff2 = to.h ? (to.h/2 + 6) : 20;

  if (Math.abs(dx) < 30) {
    return `M ${from.x} ${from.y + yOff} L ${to.x} ${to.y - yOff2}`;
  }
  if (dy > 0 && Math.abs(dx) < 200) {
    const midY = (from.y + to.y) / 2;
    return `M ${from.x} ${from.y + yOff} C ${from.x} ${midY}, ${to.x} ${midY}, ${to.x} ${to.y - yOff2}`;
  }
  if (to.x > from.x) {
    const midX = (from.x + to.x) / 2;
    return `M ${from.x} ${from.y + yOff} L ${from.x} ${from.y + 40} L ${to.x} ${from.y + 40} L ${to.x} ${to.y - yOff2}`;
  } else {
    return `M ${from.x} ${from.y + yOff} L ${from.x} ${from.y + 30} L ${to.x} ${from.y + 30} L ${to.x} ${to.y - yOff2}`;
  }
}

function updateFlowchartActive(activeId) {
  const svg = $('#flowchart');
  const nodes = svg._nodes || [];
  const edges = svg._edges || [];

  svg.querySelectorAll('.flow-node rect').forEach(r => {
    r.setAttribute('stroke-width', '1.5');
    r.setAttribute('opacity', '0.6');
  });
  svg.querySelectorAll('.flow-edge').forEach(e => {
    e.setAttribute('stroke', '#3a3d52');
    e.setAttribute('stroke-width', '2');
    e.setAttribute('marker-end', 'url(#arrow)');
  });
  svg.querySelectorAll('.flow-node text').forEach(t => {
    t.setAttribute('opacity', '0.6');
  });

  const activeIdx = nodes.findIndex(n => n.id === activeId);
  if (activeIdx < 0) return;

  for (let i = 0; i <= activeIdx; i++) {
    const n = nodes[i];
    const g = svg.querySelector(`g[data-id="${n.id}"]`);
    if (!g) continue;
    const rect = g.querySelector('rect');
    const texts = g.querySelectorAll('text');
    if (rect) {
      rect.setAttribute('stroke-width', '2.5');
      rect.setAttribute('opacity', '1');
    }
    texts.forEach(t => t.setAttribute('opacity', '1'));
  }

  const curG = svg.querySelector(`g[data-id="${activeId}"]`);
  if (curG) {
    const rect = curG.querySelector('rect');
    if (rect) {
      rect.setAttribute('stroke-width', '3');
      rect.setAttribute('filter', 'url(#glow-active)');
      rect.setAttribute('stroke', 'url(#g-active)');
    }
  }

  edges.forEach(e => {
    const toIdx = nodes.findIndex(n => n.id === e.to);
    if (toIdx <= activeIdx && toIdx >= 0) {
      const edge = svg.querySelector(`path[data-from="${e.from}"][data-to="${e.to}"]`);
      if (edge) {
        edge.setAttribute('stroke', '#7c5cfc');
        edge.setAttribute('stroke-width', '2.5');
        edge.setAttribute('marker-end', 'url(#arrow-active)');
      }
    }
  });
}

// == Right Panel: Preview ==
function renderPreview(step) {
  const container = $('#preview-content');
  $('#preview-step-name').textContent = step.label;

  if (!step.nonempty) {
    container.innerHTML = `
      <div class="preview-placeholder">
        <span>${step.exists ? '📂' : '📁'}</span>
        <p>${step.exists ? 'Ordner ist leer' : 'Ordner existiert noch nicht'}<br>
        <small style="color:var(--text-muted)">${step.dir}/</small></p>
      </div>`;
    return;
  }

  let html = '';

  if (step.scripts && step.scripts.length) {
    html += `<div class="preview-section">
      <div class="preview-section-title">Verwendete Skripte</div>`;
    step.scripts.forEach(s => {
      const scriptPath = s.endsWith('.sh')
        ? '/api/file/src/scripts/' + s
        : '/api/file/src/python/' + s;
      html += `<a class="preview-file" href="${scriptPath}" target="_blank">
        <span class="preview-file-icon">📜</span>
        <div class="preview-file-info">
          <div class="preview-file-name">${s}</div>
        </div>
        <span class="preview-file-dl">↗</span>
      </a>`;
    });
    html += `</div>`;
  }

  if (step.preview && step.preview.images && step.preview.images.length) {
    html += `<div class="preview-section">
      <div class="preview-section-title">Bilder (${step.preview.images.length})</div>
      <div class="preview-image-grid">`;
    step.preview.images.forEach(img => {
      const p = '/api/file/' + img.path;
      html += `<div class="preview-image-wrap" onclick="openLightbox('${p}')">
        <img src="${p}" alt="${img.name}" loading="lazy">
        <div class="preview-image-label">${img.name}</div>
      </div>`;
    });
    html += `</div></div>`;
  }

  if (step.preview && step.preview.video) {
    const v = step.preview.video;
    html += `<div class="preview-section">
      <div class="preview-section-title">Video</div>
      <div class="preview-video-wrap">
        <video controls preload="metadata">
          <source src="/api/file/${v.path}" type="video/mp4">
        </video>
        <div class="preview-video-label">${v.name} (${fmtSize(v.size)})</div>
      </div>
    </div>`;
  }

  if (step.preview && step.preview.ply) {
    const p = step.preview.ply;
    html += `<div class="preview-section">
      <div class="preview-section-title">Punktwolke / Mesh</div>
      <a class="preview-file" href="/api/file/${p.path}" download>
        <span class="preview-file-icon">🔷</span>
        <div class="preview-file-info">
          <div class="preview-file-name">${p.name}</div>
          <div class="preview-file-size">${fmtSize(p.size)}</div>
        </div>
        <span class="preview-file-dl">⬇</span>
      </a>
    </div>`;
  }

  if (step.preview && step.preview.checkpoints) {
    html += `<div class="preview-section">
      <div class="preview-section-title">Model Checkpoints</div>`;
    step.preview.checkpoints.forEach(f => {
      html += `<a class="preview-file" href="/api/file/${f.path}" download>
        <span class="preview-file-icon">🧠</span>
        <div class="preview-file-info">
          <div class="preview-file-name">${f.name}</div>
          <div class="preview-file-size">${fmtSize(f.size)}</div>
        </div>
        <span class="preview-file-dl">⬇</span>
      </a>`;
    });
    html += `</div>`;
  }

  if (step.preview && step.preview.csv) {
    const f = step.preview.csv;
    html += `<div class="preview-section">
      <div class="preview-section-title">Tabellendaten</div>
      <a class="preview-file" href="/api/file/${f.path}" target="_blank">
        <span class="preview-file-icon">📊</span>
        <div class="preview-file-info">
          <div class="preview-file-name">${f.name}</div>
          <div class="preview-file-size">${fmtSize(f.size)}</div>
        </div>
        <span class="preview-file-dl">↗</span>
      </a>
    </div>`;
  }

  if (step.preview && step.preview.geojson) {
    const f = step.preview.geojson;
    html += `<div class="preview-section">
      <div class="preview-section-title">GIS-Daten</div>
      <a class="preview-file" href="/api/file/${f.path}" target="_blank">
        <span class="preview-file-icon">🌍</span>
        <div class="preview-file-info">
          <div class="preview-file-name">${f.name}</div>
          <div class="preview-file-size">${fmtSize(f.size)}</div>
        </div>
        <span class="preview-file-dl">↗</span>
      </a>
    </div>`;
  }

  if (step.files && step.files.length) {
      const total = step.total_file_count || step.file_count;
      html += `<div class="preview-section">
      <div class="preview-section-title">Alle Dateien (${total})</div>`;
    const showCount = Math.min(step.files.length, total > 100 ? 8 : 20);
    step.files.slice(0, showCount).forEach(f => {
      if (f.is_dir) return;
      const icon = f.name.match(/\.(ply|obj)$/i) ? '🔷' :
                   f.name.match(/\.(jpg|jpeg|png|gif)$/i) ? '🖼️' :
                   f.name.match(/\.(mp4|mov)$/i) ? '🎥' :
                   f.name.match(/\.pth$/i) ? '🧠' :
                   f.name.match(/\.(csv|geojson|json)$/i) ? '📊' : '📄';
      html += `<a class="preview-file" href="/api/file/${f.path}" ${f.name.match(/\.(png|jpg|jpeg|gif|mp4|mov)$/i) ? '' : 'download'}>
        <span class="preview-file-icon">${icon}</span>
        <div class="preview-file-info">
          <div class="preview-file-name">${f.name}</div>
          <div class="preview-file-size">${fmtSize(f.size)}</div>
        </div>
        <span class="preview-file-dl">${f.name.match(/\.(png|jpg|jpeg|gif)$/i) ? '👁' : '⬇'}</span>
      </a>`;
    });
    if (total > showCount) {
      html += `<div style="text-align:center;color:var(--text-muted);font-size:11px;padding:8px;">
        + ${total - showCount} weitere Dateien</div>`;
    }
    html += `</div>`;
  }

  container.innerHTML = html || `<div class="preview-placeholder">
    <span>📭</span><p>Keine Vorschau verfügbar</p></div>`;
}

// == Lightbox ==
function openLightbox(src) {
  let lb = $('#lightbox');
  if (!lb) {
    lb = document.createElement('div');
    lb.id = 'lightbox';
    lb.className = 'lightbox';
    lb.innerHTML = '<button class="lightbox-close" onclick="closeLightbox()">&times;</button><img alt="Vorschau">';
    lb.addEventListener('click', closeLightbox);
    document.body.appendChild(lb);
  }
  lb.querySelector('img').src = src;
  lb.classList.add('open');
}

function closeLightbox() {
  const lb = $('#lightbox');
  if (lb) lb.classList.remove('open');
}

// == Footer ==
function updateFooter() {
  const completed = allSteps.filter(s => s.nonempty).length;
  const total = allSteps.length;
  const last = allSteps.filter(s => s.nonempty).pop();
  let info = `${completed}/${total} Schritte abgeschlossen`;
  if (last) info += ` · Letzter: ${last.label}`;
  const dataDirs = allSteps.filter(s => s.exists).length;
  info += ` · ${dataDirs}/${total} Datenordner vorhanden`;
  $('#footer-info').textContent = info;

  const dot = $('#status-dot');
  if (completed === 0) { dot.style.background = 'var(--red)'; dot.style.boxShadow = '0 0 8px rgba(248,113,113,0.4)'; }
  else if (completed === total) { dot.style.background = 'var(--green)'; dot.style.boxShadow = '0 0 8px rgba(52,211,153,0.4)'; }
  else { dot.style.background = 'var(--yellow)'; dot.style.boxShadow = '0 0 8px rgba(251,191,36,0.4)'; }
}

// == Scripts Panel ==
function renderScriptList() {
  const list = $('#script-list');
  list.innerHTML = '';
  allScripts.forEach((s, i) => {
    const el = document.createElement('div');
    el.className = 'script-item' + (s.id === selectedScriptId ? ' active' : '');
    el.dataset.index = i;
    el.innerHTML = `
      <span class="script-icon">${getScriptIcon(s.id)}</span>
      <span class="script-name">${s.name}</span>
      <div class="script-tooltip"><strong>${s.name}</strong>${s.description}</div>`;
    el.addEventListener('click', () => selectScript(s.id));
    list.appendChild(el);
  });
}

function getScriptIcon(id) {
  return { run_pipeline: '▶', run_from_sts: '⏩', run_sam3: '🎯', clean_data: '🧹' }[id] || '📜';
}

function selectScript(scriptId) {
  selectedScriptId = scriptId;
  $$('.script-item').forEach(el => {
    const idx = parseInt(el.dataset.index);
    el.classList.toggle('active', allScripts[idx] && allScripts[idx].id === scriptId);
  });
  const script = allScripts.find(s => s.id === scriptId);
  if (!script) return;
  showScriptDetail(script);
}

function showScriptDetail(script) {
  const detail = $('#script-detail');
  const running = scriptSessionId !== null && scriptEventSource !== null;

  // Info section
  const infoHtml = `
    <div style="display:flex;justify-content:space-between;align-items:flex-start">
      <div class="script-desc">${script.description}</div>
      <div class="script-controls">
        <button class="script-btn run-btn" id="btn-run-script" ${running ? 'disabled' : ''}
          onclick="runScript('${script.id}')">&#9654; Ausführen</button>
        <button class="script-btn stop-btn" id="btn-stop-script" style="${running ? '' : 'display:none'}"
          onclick="stopScript()">&#9632; Stop</button>
      </div>
    </div>`;
  $('#script-info').innerHTML = infoHtml;
  $('#script-info').style.display = '';

  // Progress steps
  const progressHtml = `<div class="preview-section-title">Schritte</div>` +
    script.steps.map((step, i) =>
      `<div class="progress-step" data-step="${i}">
        <span class="step-dot"></span> ${step}
      </div>`
    ).join('');
  $('#script-progress').innerHTML = progressHtml;
  $('#script-progress').style.display = '';

  // Terminal
  const term = $('#script-terminal');
  term.innerHTML = '<div class="terminal-line info"># Wähle "Ausführen" um das Skript zu starten</div>';
  term.style.display = '';

  // Input area
  const inputArea = $('#script-input-area');
  inputArea.innerHTML = `
    <input type="text" id="script-input" placeholder="Eingabe für das Skript..." ${running ? '' : 'disabled'}>
    <button id="script-send-btn" ${running ? '' : 'disabled'} onclick="sendScriptInput()">Senden</button>`;
  inputArea.style.display = '';
  inputArea.querySelector('#script-input').addEventListener('keydown', e => {
    if (e.key === 'Enter') sendScriptInput();
  });

  // Remove placeholder
  const placeholder = detail.querySelector('.script-info-placeholder');
  if (placeholder) placeholder.style.display = 'none';

  $('#script-status').textContent = running ? 'Läuft...' : 'Bereit';
}

function appendTerminal(text, className) {
  const term = $('#script-terminal');
  const lines = text.split('\n');
  lines.forEach(line => {
    if (line === '') return;
    const div = document.createElement('div');
    div.className = 'terminal-line ' + (className || '');
    div.textContent = line;
    term.appendChild(div);
  });
  term.scrollTop = term.scrollHeight;
}

function setProgressStep(index, state) {
  const steps = $$('.progress-step');
  steps.forEach((el, i) => {
    el.classList.remove('done', 'active');
    if (i < index) el.classList.add('done');
    else if (i === index) el.classList.add('active');
  });
}

// == Script Execution ==
async function runScript(scriptId) {
  const runBtn = $('#btn-run-script');
  const stopBtn = $('#btn-stop-script');
  runBtn.disabled = true;
  runBtn.textContent = '⏳ Starte...';

  try {
    const res = await fetch('/api/script/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ script_id: scriptId })
    });
    const data = await res.json();
    if (data.error) { throw new Error(data.error); }

    scriptSessionId = data.session_id;
    runBtn.style.display = 'none';
    stopBtn.style.display = '';
    $('#script-status').textContent = 'Läuft...';
    $('#script-input').disabled = false;
    $('#script-send-btn').disabled = false;

    const term = $('#script-terminal');
    term.innerHTML = '';
    setProgressStep(0, 'active');

    // Connect to SSE stream
    scriptEventSource = new EventSource('/api/script/stream/' + scriptSessionId);
    let currentStepIndex = 0;
    let buffer = '';

    scriptEventSource.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      if (msg.type === 'heartbeat') return;
      if (msg.type === 'output') {
        appendTerminal(msg.data);
        buffer += msg.data;
        // Try to detect progress from output keywords
        const script = allScripts.find(s => s.id === scriptId);
        if (script) {
          const lower = buffer.toLowerCase();
          script.steps.forEach((_, i) => {
            const keywords = ['gcp', 'sam 3', 'sam3', 'colmap', 'cloudcompare',
              'sts', 'training', 'sugar', 'meshing', 'dgtal', 'centerline',
              'gdal', 'gis', 'berein', 'clean', 'lösch', 'hf cache'];
            // Check if this step index seems active based on cumulative output
          });
        }
      }
      if (msg.type === 'exit') {
        scriptEventSource.close();
        scriptEventSource = null;
        scriptSessionId = null;
        runBtn.style.display = '';
        stopBtn.style.display = 'none';
        runBtn.disabled = false;
        runBtn.textContent = '▶ Ausführen';
        $('#script-status').textContent = msg.data === 0 ? 'Abgeschlossen' : 'Fehler';
        $('#script-input').disabled = true;
        $('#script-send-btn').disabled = true;
        if (msg.data === 0) {
          appendTerminal('\n[Prozess beendet mit Exit-Code 0]', 'success');
          $$('.progress-step').forEach(el => el.classList.add('done'));
          $$('.progress-step').forEach(el => el.classList.remove('active'));
        } else {
          appendTerminal(`\n[Prozess beendet mit Exit-Code ${msg.data}]`, 'error');
        }
      }
    };

    scriptEventSource.onerror = () => {
      if (scriptEventSource) {
        scriptEventSource.close();
        scriptEventSource = null;
      }
      scriptSessionId = null;
      runBtn.style.display = '';
      stopBtn.style.display = 'none';
      runBtn.disabled = false;
      runBtn.textContent = '▶ Ausführen';
      $('#script-status').textContent = 'Getrennt';
      $('#script-input').disabled = true;
      $('#script-send-btn').disabled = true;
    };

  } catch (e) {
    appendTerminal('\n[FEHLER] ' + e.message, 'error');
    runBtn.disabled = false;
    runBtn.textContent = '▶ Ausführen';
    $('#script-status').textContent = 'Fehler';
  }
}

async function stopScript() {
  if (!scriptSessionId) return;
  try {
    await fetch('/api/script/stop', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ session_id: scriptSessionId })
    });
    appendTerminal('\n[Skript wird gestoppt...]', 'error');
  } catch (e) {
    console.error('Stop failed:', e);
  }
}

async function sendScriptInput() {
  if (!scriptSessionId) return;
  const input = $('#script-input');
  const text = input.value;
  if (!text.trim()) return;
  input.value = '';
  try {
    await fetch('/api/script/input/' + scriptSessionId, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ input: text })
    });
    appendTerminal('> ' + text, 'prompt');
  } catch (e) {
    console.error('Input failed:', e);
  }
}

// == Init ==
document.addEventListener('DOMContentLoaded', loadAll);
