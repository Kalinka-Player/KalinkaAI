/* Standalone review prototype. All data and playback state are local fixtures. */
(() => {
  'use strict';
  const $ = s => document.querySelector(s);
  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const paths = {
    back:'<path d="m14 6-6 6 6 6M8 12h13"/>', right:'<path d="m9 5 7 7-7 7"/>',
    play:'<path d="m8 5 11 7-11 7Z"/>', pause:'<path d="M8 5v14M16 5v14"/>',
    next:'<path d="m5 5 10 7-10 7ZM19 5v14"/>', previous:'<path d="m19 5-10 7 10 7ZM5 5v14"/>',
    search:'<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
    more:'<circle cx="12" cy="5" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="12" cy="19" r="1"/>',
    home:'<path d="m3 10 9-7 9 7v10H3ZM9 20v-7h6v7"/>',
    folder:'<path d="M3 6h7l2 3h9v11H3Z"/>', music:'<path d="M9 17V5l11-2v12M9 8l11-2"/><ellipse cx="6" cy="18" rx="3" ry="2"/><ellipse cx="17" cy="16" rx="3" ry="2"/>',
    add:'<path d="M3 6h12M3 12h8M3 18h8M18 11v10M13 16h10"/>',
    close:'<path d="m6 6 12 12M18 6 6 18"/>',
    pin:'<path d="M8 3h8l-1 6 4 4H5l4-4ZM12 13v8"/>',
    tune:'<path d="M4 6h7M15 6h5M4 12h2M10 12h10M4 18h11M19 18h1M11 3v6M6 9v6M15 15v6"/>',
    check:'<path d="m5 12 4 4L19 6"/>', edit:'<path d="m15 4 5 5M4 20l2-6L17 3l4 4L10 18Z"/>',
    sparkles:'<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5ZM20 3v4M18 5h4"/>',
    collection:'<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    album:'<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>',
    person:'<circle cx="12" cy="8" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>'
  };
  const icon = name => `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.music}</svg>`;
  const ib = (action, symbol, label, attrs='') => `<button class="icon-button" data-action="${action}" data-focus-key="${esc(`${action}:${attrs || label}`)}" aria-label="${esc(label)}" title="${esc(label)}" ${attrs}>${icon(symbol)}</button>`;
  const art = (n=0, portrait=false) => {
    const colors = [['#a65561','#342328','#d3b2a0'],['#536e72','#192b31','#a0b8af'],['#9a8359','#302921','#d5c6a3'],['#787394','#28263a','#bab4ce']][n % 4];
    return `<svg class="art" viewBox="0 0 240 240" aria-hidden="true"><rect width="240" height="240" fill="${colors[1]}"/><path d="M-20 190 140-20 260 170 260 260H-20Z" fill="${colors[0]}"/>${portrait ? `<circle cx="120" cy="88" r="38" fill="${colors[2]}"/><path d="M43 240c0-125 154-125 154 0" fill="${colors[1]}"/>` : `<circle cx="158" cy="82" r="48" fill="${colors[2]}"/><path d="M-20 190 112 64 252 244Z" fill="${colors[1]}" opacity=".78"/><path d="M0 202h240M0 214h240M0 226h240" stroke="${colors[2]}" opacity=".36"/><rect x="23" y="23" width="194" height="194" fill="none" stroke="${colors[2]}" opacity=".25"/>`}</svg>`;
  };
  // Fictional catalogs demonstrate source identity, including identical releases.
  // Display names/icons are fixture metadata, not provider-specific UI behavior.
  const sources = [
    {id:'library',name:'My Library',icon:'folder',capabilities:['ai_search']},
    {id:'qobuz',name:'Qobuz',icon:'music',capabilities:['ai_search']},
    {id:'tidal',name:'Tidal',icon:'music',capabilities:[]}
  ];
  const sourceInfo = value => sources.find(s=>s.id===value||s.name===value);
  // The built-in collection search origin is independent of its tracks' sources.
  const searchOrigins = [...sources,{id:'collections',name:'Your collections',icon:'collection'}];
  const genres = ['Jazz','Ambient','Electronic','Classical'];
  const resultKinds = {all:'Both',matches:'Name matching',recommendations:'Recommendations'};
  const filterStorageKey = 'kalinka-navigation-proposal:search-filters:v1';
  const cleanFilters = value => ({
    kind:Object.hasOwn(resultKinds,value?.kind)?value.kind:'all',
    sources:searchOrigins.filter(s=>Array.isArray(value?.sources)&&value.sources.includes(s.id)).map(s=>s.id),
    genres:genres.filter(g=>Array.isArray(value?.genres)&&value.genres.includes(g))
  });
  let savedFilters;
  try {savedFilters=cleanFilters(JSON.parse(localStorage.getItem(filterStorageKey)));}
  catch {savedFilters=cleanFilters();}
  const filtersFor = r => cleanFilters(r.filters);
  const filterCount = f => (f.kind==='all'?0:1)+f.sources.length+f.genres.length;
  const includesOrigin = (f,id) => !f.sources.length||f.sources.includes(id);
  const includesGenre = (f,values) => !f.genres.length||values.some(g=>f.genres.includes(g));
  function rememberFilters(filters){
    savedFilters=cleanFilters(filters);
    try {localStorage.setItem(filterStorageKey,JSON.stringify(savedFilters));} catch { /* The prototype also works without storage. */ }
  }
  const artists = [
    {id:0,name:'Mara Vale',sourceId:'library',art:0},
    {id:1,name:'The North Room',sourceId:'library',art:1},
    {id:2,name:'Mara Vale',sourceId:'qobuz',art:0},
    {id:3,name:'Mara Vale',sourceId:'tidal',art:0}
  ];
  const libraryAlbums = [
    {id:0,title:'Quiet Geometry',artist:'Mara Vale',artistId:0,year:2024,genre:'Jazz',art:0},
    {id:1,title:'Between the Lines',artist:'Mara Vale',artistId:0,year:2022,genre:'Jazz',art:1},
    {id:2,title:'The Long Way Home',artist:'Mara Vale',artistId:0,year:2020,genre:'Ambient',art:2},
    {id:3,title:'Night Windows',artist:'The North Room',artistId:1,year:2025,genre:'Ambient',art:3},
    {id:4,title:'Still Water',artist:'The North Room',artistId:1,year:2023,genre:'Jazz',art:1},
    {id:5,title:'A Place to Begin',artist:'The North Room',artistId:1,year:2021,genre:'Electronic',art:2}
  ].map(a=>({...a,sourceId:'library',trackSet:a.id%3,resultOrder:a.id}));
  const albums = [
    ...libraryAlbums,
    ...[0,1,2].map((id,i)=>({...libraryAlbums[id],id:6+i,artistId:2,sourceId:'qobuz'})),
    ...[0,1].map((id,i)=>({...libraryAlbums[id],id:9+i,artistId:3,sourceId:'tidal'}))
  ];
  const names = [['First Light','Quiet Geometry','The Space Between','Small Hours','A Kind of Blue Sky','Slow Turning','Last Train North','After the Rain'],['Paper Lanterns','Between the Lines','Three in the Morning','Open Doors','Winter Sun','The Other Side','Motionless','Returning'],['The Long Way Home','Passing Clouds','Northern Shore','Low Tide','A Small Distance','The Arrival','Silence in Colour','Stay a While']];
  const seconds = [264,312,218,326,284,247,305,231];
  const tracks = albums.flatMap(a => names[a.trackSet].map((title,i)=>({id:`${a.id}-${i}`,title,albumId:a.id,artistId:a.artistId,artist:a.artist,sourceId:a.sourceId,seconds:seconds[i],number:i+1,resultOrder:a.resultOrder*8+i})));
  const collection = {title:'After hours',description:'A few favourites for the quieter part of the evening.',owner:'You',ids:['0-0','1-3','6-2','0-6','2-1','9-4'],editable:true};
  const providerPlaylist = {title:'Late Night Jazz',owner:'Guest curator',sourceId:'qobuz',ids:['6-0','7-3','8-2','6-6','7-1','8-4']};
  const byId = id => tracks.find(t=>t.id===id);
  const albumTracks = id => tracks.filter(t=>t.albumId===Number(id));
  const collectionTracks = () => collection.ids.map(byId);
  const providerPlaylistTracks = () => providerPlaylist.ids.map(byId);
  // This is fixture support, not a claim about these plugins' deployed capabilities.
  // Every query receives a snapshot: no intent classifier or keyword gate.
  const suggestionSnapshot = () => Object.fromEntries(sources
    .filter(s=>s.capabilities.includes('ai_search'))
    .map(s=>[s.id,tracks.filter(t=>t.sourceId===s.id).slice(0,20).map(t=>t.id)]));
  const suggestionsFor = (r,sourceId) => (r.suggestions?.[sourceId]||[]).map(byId)
    .filter(t=>includesGenre(filtersFor(r),[albums[t.albumId].genre]));
  const duration = list => {const total=list.reduce((sum,t)=>sum+t.seconds,0);return `${Math.floor(total/60)} min`;};
  const time = n => `${Math.floor(n/60)}:${String(n%60).padStart(2,'0')}`;
  const source = (value='library') => {const info=sourceInfo(value);return `<span class="source">${icon(info?.icon||'folder')}${esc(info?.name||value)}</span>`;};
  const pageTitle = r => {
    switch(r.kind){
      case 'home':return 'Home';
      case 'source':return sourceInfo(r.provider)?.name||'My Library';
      case 'catalog':return r.category||'Recently added';
      case 'album':return albums[r.id||0].title;
      case 'artist':return artists[r.id||0].name;
      case 'collection':return collection.title;
      case 'playlist':return providerPlaylist.title;
      case 'suggestions':return `Inspired · ${sourceInfo(r.sourceId).name}`;
      case 'search':return `Search: ${r.query||'Mara Vale'}`;
      case 'folder':return r.name||'Music folders';
      default:return 'Home';
    }
  };
  const routes = [{kind:'home',scroll:0}]; let position=0;
  const state = {queue:[tracks[0]],at:0,playing:false,playerTab:'playing',pinned:true};
  const current = () => routes[position];
  let toastTimer, pendingDialogAction, dialogFocus, filterDraft;
  const scroll = $('#page-scroll');
  history.replaceState({kalinkaConcept:0},'',location.href);
  function stash(){current().scroll=scroll.scrollTop;current().focus=document.activeElement?.dataset.focusKey;}
  function open(route){stash();routes.splice(position+1);routes.push({scroll:0,...(route.kind==='search'?{suggestions:suggestionSnapshot(),filters:cleanFilters(savedFilters)}:{}),...route});position++;history.pushState({kalinkaConcept:position},'',location.href);render();}
  function back(){if($('#action-dialog').open){history.back();return;}if(position>0){stash();history.back();}}
  function goHome(){if($('#action-dialog').open){closeDialog(()=>goHome());return;}if(position>0){stash();history.go(-position);}else{scroll.scrollTo({top:0});}}
  window.addEventListener('popstate',event=>{
    const target=event.state?.kalinkaConcept;
    if(!Number.isInteger(target)||!routes[target])return;
    const dialog=$('#action-dialog');
    if(dialog.open){dialog.close();filterDraft=null;document.querySelectorAll('[data-action="search-filters"]').forEach(b=>b.setAttribute('aria-expanded','false'));dialogFocus?.focus({preventScroll:true});}
    if(target!==position){stash();position=target;render(true);}
    const run=pendingDialogAction;pendingDialogAction=null;if(run)run();
  });
  function toast(text){$('#toast').textContent=text;$('#toast').classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('#toast').classList.remove('visible'),2600);}
  function closeDialog(after){pendingDialogAction=after;if($('#action-dialog').open)history.back();else if(after){pendingDialogAction=null;after();}}
  function positionDialog(){
    const dialog=$('#action-dialog');if(!dialog.open)return;
    const panel=$('.browse-pane').getBoundingClientRect();
    const left=Math.max(16,panel.left+16),right=Math.min(innerWidth-16,panel.right-16);
    const filtering=dialog.classList.contains('filter-dialog');
    const top=Math.max(16,filtering?$('#appbar').getBoundingClientRect().bottom+8:panel.top+16),bottom=Math.min(innerHeight-16,panel.bottom-16);
    dialog.style.width=`${Math.min(filtering?480:420,right-left)}px`;
    dialog.style.maxHeight=`${Math.max(48,bottom-top)}px`;
    dialog.style.left=`${filtering?right-dialog.offsetWidth:left+(right-left-dialog.offsetWidth)/2}px`;
    dialog.style.top=`${filtering?top:Math.max(top,bottom-dialog.offsetHeight)}px`;
  }
  function showDialog(title,body,filtering=false){dialogFocus=document.activeElement;$('#action-dialog').classList.toggle('filter-dialog',filtering);$('#action-dialog').classList.toggle('large-text',$('#prototype').classList.contains('large-text'));$('#dialog-body').innerHTML=`<div class="dialog-heading"><h2 id="dialog-title">${esc(title)}</h2>${ib('close-dialog','close','Close')}</div>${body}`;history.pushState({kalinkaConcept:position,dialog:true},'',location.href);$('#action-dialog').showModal();positionDialog();}
  function filterButton(r){
    const count=filterCount(filtersFor(r));
    return `<button class="search-filter-button" data-action="search-filters" data-focus-key="search-filters" aria-label="Search and filters${count?`, ${count} active`:''}" aria-haspopup="dialog" aria-expanded="false">${icon('search')}${icon('tune')}${count?`<span class="filter-count">${count}</span>`:''}</button>`;
  }
  function appliedFilters(r){
    const f=filtersFor(r);
    const chip=(facet,value,label)=>`<button class="applied-chip" data-action="remove-search-filter" data-facet="${facet}" data-value="${value}" aria-label="Remove filter ${esc(label)}">${esc(label)}${icon('close')}</button>`;
    return `<div class="applied-filters" aria-label="Current search and applied filters"><button class="applied-chip query-chip" data-action="search-filters" aria-label="Edit search: ${esc(r.query)}">${icon('search')}<span>“${esc(r.query)}”</span></button>${f.kind==='all'?'':chip('kind',f.kind,resultKinds[f.kind])}${f.sources.map(id=>chip('sources',id,searchOrigins.find(s=>s.id===id).name)).join('')}${f.genres.map(g=>chip('genres',g,g)).join('')}${filterCount(f)>1?'<button class="reset-filters" data-action="reset-search-filters">Reset all</button>':''}</div>`;
  }
  function filterChoices(){
    const choice=(facet,value,label,symbol='')=>{
      const active=facet==='kind'?filterDraft.kind===value:filterDraft[facet].includes(value);
      return `<button type="button" class="filter-choice" data-action="draft-filter" data-facet="${facet}" data-value="${value}" aria-pressed="${active}">${active?icon('check'):symbol?icon(symbol):`<span class="empty-check">${icon('check')}</span>`}${esc(label)}</button>`;
    };
    return `<fieldset><legend>Results</legend><div class="filter-options">${Object.entries(resultKinds).map(([value,label])=>choice('kind',value,label)).join('')}</div></fieldset><fieldset><legend>Sources</legend><p class="filter-hint">Choose any combination. None selected means all sources.</p><div class="filter-options">${searchOrigins.map(s=>choice('sources',s.id,s.name,s.icon)).join('')}</div></fieldset><fieldset><legend>Genres</legend><p class="filter-hint">None selected means all genres.</p><div class="filter-options">${genres.map(g=>choice('genres',g,g)).join('')}</div></fieldset>`;
  }
  function showSearchFilters(){
    // The review page has controls above the app; make room in short viewports.
    if($('#appbar').getBoundingClientRect().bottom>innerHeight-260)$('#prototype').scrollIntoView({block:'start'});
    filterDraft=current().kind==='search'?filtersFor(current()):cleanFilters(savedFilters);
    const query=current().kind==='search'?current().query:'';
    showDialog('Search & filters',`<form id="search-filter-form"><div class="filter-body"><label class="filter-query-label" for="filter-query">Search</label><div class="filter-query">${icon('search')}<input id="filter-query" name="query" value="${esc(query)}" placeholder="A mood, artist, album or collection…" required></div><div id="filter-choices">${filterChoices()}</div><p class="filter-hint remember-note">Your filter choices are remembered for the next search.</p></div><footer class="filter-footer"><button type="button" class="reset-filters" data-action="reset-draft-filters">Reset filters</button><button type="button" class="pill" data-action="close-dialog">Cancel</button><button class="pill filled" type="submit">Show results</button></footer></form>`,true);
    document.querySelectorAll('[data-action="search-filters"]').forEach(b=>b.setAttribute('aria-expanded','true'));
    $('#filter-query').focus({preventScroll:true});
  }
  function updateSearchFilters(filters){
    stash();current().filters=cleanFilters(filters);rememberFilters(filters);
    if(current().matchSource&&!nameEntries(current()).some(e=>e.sourceId===current().matchSource))current().matchSource=null;
    current().scroll=0;render();
  }
  new ResizeObserver(positionDialog).observe($('.browse-pane'));
  window.addEventListener('resize',positionDialog);
  window.addEventListener('scroll',positionDialog);
  $('#action-dialog').addEventListener('cancel',e=>{e.preventDefault();closeDialog();});
  $('#action-dialog').addEventListener('click',e=>{const rect=e.currentTarget.getBoundingClientRect();if(e.target===e.currentTarget&&(e.clientX<rect.left||e.clientX>rect.right||e.clientY<rect.top||e.clientY>rect.bottom))closeDialog();});
  function card(a){return `<article class="entity-card"><button class="cover-button" data-action="album" data-id="${a.id}" data-focus-key="album-cover-${a.id}" aria-label="Open ${esc(a.title)}">${art(a.art)}</button><div class="card-foot"><button class="card-label" data-action="album" data-id="${a.id}" data-focus-key="album-title-${a.id}"><strong>${esc(a.title)}</strong><small>${esc(a.artist)}<br>${a.year} · Album</small></button>${ib('play-album','play',`Play ${a.title}`,`data-id="${a.id}"`)}</div></article>`;}
  function albumRow(a){return `<div class="entity-row"><button class="row-open" data-action="album" data-id="${a.id}" data-focus-key="album-row-${a.id}"><span class="row-art">${art(a.art)}</span><span class="row-copy"><strong>${esc(a.title)}</strong><small>Album · ${esc(a.artist)} · ${a.year}</small>${source(a.sourceId)}</span>${icon('right')}</button>${ib('play-album','play',`Play ${a.title}`,`data-id="${a.id}"`)}${ib('album-menu','more',`Actions for ${a.title}`,`data-id="${a.id}"`)}</div>`;}
  function artistRow(id){
    const a=artists[id],count=albums.filter(x=>x.artistId===id).length;
    return `<div class="entity-row"><button class="row-open" data-action="artist" data-id="${id}" data-focus-key="artist-row-${id}"><span class="row-art" style="border-radius:50%">${art(a.art,true)}</span><span class="row-copy"><strong>${a.name}</strong><small>Artist · ${count} albums</small>${source(a.sourceId)}</span>${icon('right')}</button></div>`;
  }
  function collectionRow(){return `<div class="entity-row"><button class="row-open" data-action="collection" data-focus-key="collection"><span class="row-art">${collectionArt()}</span><span class="row-copy"><strong>${esc(collection.title)}</strong><small>Collection · ${collection.ids.length} tracks · ${duration(collectionTracks())}</small><span class="source">${icon('collection')}Mixed sources</span></span>${icon('right')}</button>${ib('play-collection','play',`Play ${collection.title}`)}${ib('collection-menu','more','Collection actions')}</div>`;}
  function trackRows(list,context='single',showSource=true,showArt=false){
    return list.map(t=>`<div class="track-row${state.playing&&state.queue[state.at]?.id===t.id?' current':''}"><button class="track-play" data-action="play-track" data-id="${t.id}" data-context="${context}" data-focus-key="track-${context}-${t.id}" aria-label="Play ${esc(t.title)}"><span class="track-number">${icon('play')}</span>${showArt?`<span class="track-art">${art(albums[t.albumId].art)}</span>`:''}<span class="track-name">${context.startsWith('album')?`<small>${String(t.number).padStart(2,'0')}</small>`:''}${esc(t.title)}${context.startsWith('album')?'':`<small>${context==='name-match'?'Track · ':''}${esc(t.artist)}</small>${showSource?source(t.sourceId):''}`}</span><span class="duration">${time(t.seconds)}</span></button>${ib('track-menu','more',`Actions for ${t.title}`,`data-id="${t.id}" data-context="${context}"`)}</div>`).join('');
  }
  const grid = list => `<div class="entity-grid">${list.map(card).join('')}</div>`;
  const heading = title => `<h3 class="shelf-title">${esc(title)}</h3>`;
  const searchForm = (value='') => `<form class="search-form" data-search>${icon('search')}<label class="sr-only" for="music-query">Search all music</label><input id="music-query" name="query" placeholder="A mood, artist, album or collection…" value="${esc(value)}" autocomplete="off"><button class="icon-button" aria-label="Search music" type="submit">${icon('right')}</button></form>`;
  const tabs = (values,active) => `<div class="tabs" role="tablist">${values.map(([id,label])=>`<button role="tab" aria-selected="${id===active}" tabindex="${id===active?0:-1}" data-action="tab" data-tab="${id}">${esc(label)}</button>`).join('')}</div>`;
  function homePage(){return `<h1 class="page-title" tabindex="-1">What shall we play?</h1>${searchForm()}<section class="section">${heading('YOUR COLLECTIONS')}${collectionRow()}</section><section class="section">${heading('MUSIC SOURCES')}<div class="source-grid">${sources.map(s=>`<button class="source-tile" data-action="source" data-provider="${s.id}">${icon(s.icon)}<span>${s.name}</span>${icon('right')}</button>`).join('')}</div></section>${state.pinned?`<section class="section">${heading('RECENTLY ADDED')}<p class="small-note">My Library</p>${grid(libraryAlbums.slice(0,2))}<button class="section-link" data-action="catalog">All albums · 6 ${icon('right')}</button></section>`:''}`;}
  function sourcePage(r){const info=sourceInfo(r.provider)||sources[0];return `<p class="eyebrow">MUSIC SOURCE</p><h1 class="page-title" tabindex="-1">${esc(info.name)}</h1><p class="page-subtitle">Browse the catalogs available from this source.</p>${['Recently added','Albums','Artists','Playlists'].map((title,i)=>`<div class="entity-row"><button class="row-open" data-action="catalog" data-category="${title}" data-provider="${info.id}" data-focus-key="category-${i}"><span class="row-copy"><strong>${title}</strong></span>${icon('right')}</button></div>`).join('')}`;}
  function catalogPage(r){
    const category=r.category||'Recently added',info=sourceInfo(r.provider)||sources[0],filter=r.genre||'All genres';
    const list=albums.filter(a=>a.sourceId===info.id&&(filter==='All genres'||a.genre===filter));
    const body=category==='Artists'?artists.filter(a=>a.sourceId===info.id).map(a=>artistRow(a.id)).join(''):category==='Playlists'?'<div class="empty">No playlists in this sample catalog.</div>':list.length?grid(list):`<div class="empty"><p>No albums match this genre.</p><button class="pill" data-action="reset-filter">Clear filter</button></div>`;
    return `<p class="eyebrow">CATALOG</p><h1 class="page-title" tabindex="-1">${esc(category)}</h1>${source(info.id)}<div class="filters">${!['Artists','Playlists'].includes(category)?`<button class="pill" data-action="filter">${icon('tune')}${esc(filter)}</button>`:''}<button class="pill" data-action="pin">${icon('pin')}${state.pinned?'Unpin from Home':'Pin to Home'}</button></div>${body}`;
  }
  function albumPage(r){const a=albums[r.id||0],list=albumTracks(a.id);return `<div class="identity"><div class="identity-art">${art(a.art)}</div><div><p class="eyebrow">ALBUM</p><h1 class="page-title" tabindex="-1">${a.title}</h1><button class="artist-link" data-action="artist" data-id="${a.artistId}" data-focus-key="album-artist">${a.artist}${icon('right')}</button><p class="metadata">${a.year} · ${list.length} tracks · ${duration(list)}</p>${source(a.sourceId)}</div></div><div class="action-row"><button class="pill accent" data-action="play-album" data-id="${a.id}">${icon('play')}Play album</button><button class="pill" data-action="enqueue-album" data-id="${a.id}">${icon('add')}Enqueue</button>${ib('album-menu','more','Album actions',`data-id="${a.id}"`)}</div>${heading('TRACKS')}${trackRows(list,`album:${a.id}`)}<details class="album-info"><summary>Album information</summary><dl><dt>Year</dt><dd>${a.year}</dd><dt>Genre</dt><dd>${a.genre}</dd><dt>Duration</dt><dd>${duration(list)}</dd><dt>Source</dt><dd>${sourceInfo(a.sourceId).name}</dd></dl></details>`;}
  function artistPage(r){
    const id=r.id||0,a=artists[id],list=albums.filter(x=>x.artistId===id),tab=r.tab||'albums';
    return `<div class="identity artist"><div class="identity-art">${art(a.art,true)}</div><div><p class="eyebrow">ARTIST</p><h1 class="page-title" tabindex="-1">${a.name}</h1><p class="metadata">${list.length} albums</p>${source(a.sourceId)}</div></div>${tabs([['albums','Albums'],['tracks','Tracks']],tab)}<section role="tabpanel" aria-label="${tab==='albums'?'Albums':'Tracks'}">${tab==='albums'?grid(list):trackRows(tracks.filter(t=>t.artistId===id))}</section>`;
  }
  function collectionArt(){return `<span class="collection-art">${collectionTracks().slice(0,4).map(t=>art(albums[t.albumId].art)).join('')}</span>`;}
  function collectionPage(){
    const list=collectionTracks(),names=[...new Set(list.map(t=>sourceInfo(t.sourceId).name))];
    return `<div class="identity"><div class="identity-art">${collectionArt()}</div><div><p class="eyebrow">COLLECTION</p><h1 class="page-title" tabindex="-1">${esc(collection.title)}</h1><p class="metadata">By ${collection.owner}<br>${list.length} tracks · ${duration(list)}</p><span class="source">${icon('collection')}${names.length} music sources</span></div></div><p class="page-description">${esc(collection.description)}</p><p class="small-note">${names.join(' · ')}</p><div class="action-row"><button class="pill accent" data-action="play-collection">${icon('play')}Play collection</button><button class="pill" data-action="enqueue-collection">${icon('add')}Enqueue</button>${ib('collection-menu','more','Collection actions')}</div>${heading('TRACKS')}${trackRows(list,'collection',true,true)}`;
  }
  function playlistRow(){return `<div class="entity-row"><button class="row-open" data-action="playlist" data-focus-key="playlist"><span class="row-art">${art(1)}</span><span class="row-copy"><strong>${providerPlaylist.title}</strong><small>Playlist · ${providerPlaylist.ids.length} tracks</small>${source(providerPlaylist.sourceId)}</span>${icon('right')}</button>${ib('play-playlist','play',`Play ${providerPlaylist.title}`)}</div>`;}
  function playlistPage(){
    const list=providerPlaylistTracks();
    return `<div class="identity"><div class="identity-art">${art(1)}</div><div><p class="eyebrow">PLAYLIST</p><h1 class="page-title" tabindex="-1">${providerPlaylist.title}</h1><p class="metadata">By ${providerPlaylist.owner}<br>${list.length} tracks · ${duration(list)}</p>${source(providerPlaylist.sourceId)}</div></div><div class="action-row"><button class="pill accent" data-action="play-playlist">${icon('play')}Play playlist</button><button class="pill" data-action="enqueue-playlist">${icon('add')}Enqueue</button></div>${heading('TRACKS')}${trackRows(list,'playlist',false,true)}`;
  }
  function nameEntries(r){
    const query=(r.query||'Mara Vale').toLowerCase(),filters=filtersFor(r);
    const included=item=>includesOrigin(filters,item.sourceId);
    const matches=text=>text.toLowerCase().includes(query);
    const entries=[
      ...artists.filter(a=>included(a)&&matches(a.name)&&includesGenre(filters,albums.filter(x=>x.artistId===a.id).map(x=>x.genre))).map(a=>({kind:'artists',sourceId:a.sourceId,row:()=>artistRow(a.id)})),
      ...albums.filter(a=>included(a)&&matches(`${a.title} ${a.artist}`)&&includesGenre(filters,[a.genre])).sort((a,b)=>a.resultOrder-b.resultOrder).map(a=>({kind:'albums',sourceId:a.sourceId,row:()=>albumRow(a)})),
      ...(included(providerPlaylist)&&matches(providerPlaylist.title)&&includesGenre(filters,[])?[{kind:'playlists',sourceId:providerPlaylist.sourceId,row:playlistRow}]:[]),
      // A collection is user-owned, not owned by its first track's source.
      ...(includesOrigin(filters,'collections')&&matches(collection.title)&&includesGenre(filters,[])?[{kind:'collections',sourceId:'collections',row:collectionRow}]:[]),
      ...tracks.filter(t=>included(t)&&matches(`${t.title} ${t.artist}`)&&includesGenre(filters,[albums[t.albumId].genre])).sort((a,b)=>a.resultOrder-b.resultOrder).map(t=>({kind:'tracks',sourceId:t.sourceId,row:()=>trackRows([t],'name-match',true,true)}))
    ];
    return entries;
  }
  function suggestionGroup(r,info){
    const list=suggestionsFor(r,info.id);
    if(!list.length)return '';
    return `<section class="suggestion-group" data-source="${info.id}" aria-label="${info.name} smart suggestions"><div class="section-top"><h3 class="shelf-title">${icon(info.icon)}${info.name}<span class="tally">· ${list.length}</span></h3>${list.length>3?`<button class="section-link" data-action="all-suggestions" data-source="${info.id}" data-focus-key="suggestions-${info.id}">All ${list.length} tracks ${icon('right')}</button>`:''}</div><div class="action-row"><button class="pill accent" data-action="play-suggestions" data-source="${info.id}">${icon('play')}Play all</button><button class="pill" data-action="enqueue-suggestions" data-source="${info.id}">${icon('add')}Enqueue</button></div>${trackRows(list.slice(0,3),`suggestions:${info.id}`,false,true)}</section>`;
  }
  function searchPage(r){
    const query=r.query||'Mara Vale',filters=filtersFor(r),all=nameEntries(r);
    const present=searchOrigins.filter(s=>all.some(e=>e.sourceId===s.id));
    const picked=present.some(s=>s.id===r.matchSource)?r.matchSource:null;
    const selected=picked?all.filter(e=>e.sourceId===picked):all;
    const sourceChoices=present.length>1?`<div class="match-sources" role="group" aria-label="Show name matches from a source; recommendations stay unchanged">${[{id:'',name:'All'},...present].map(s=>`<button class="pill${(picked||'')===s.id?' accent':''}" aria-pressed="${(picked||'')===s.id}" data-action="match-source" data-source="${s.id}" data-focus-key="match-source-${s.id}">${s.icon?icon(s.icon):''}${esc(s.name)}</button>`).join('')}</div>`:'';
    const groups=r.matchesExpanded||filters.kind==='matches'?[]:sources.filter(s=>includesOrigin(filters,s.id)&&s.capabilities.includes('ai_search')&&suggestionsFor(r,s.id).length);
    const showNames=filters.kind!=='recommendations'&&(selected.length>0||filters.kind==='matches'||r.matchesExpanded);
    const emptyNames=`<div class="empty"><p>No name matches for “${esc(query)}” with these filters.</p><button class="pill" data-action="search-filters">Edit search & filters</button></div>`;
    const shown=r.matchesExpanded?selected:selected.slice(0,4);
    const names=showNames?`<section id="name-matches" class="name-matches" aria-label="Matches by name"><div class="section-top"><h3 class="shelf-title">MATCHES BY NAME <span class="tally">· ${selected.length}</span></h3>${!r.matchesExpanded&&selected.length>shown.length?`<button class="section-link" data-action="all-matches" data-focus-key="all-matches">View all ${icon('right')}</button>`:''}</div>${sourceChoices}${shown.map(e=>e.row()).join('')||emptyNames}</section>`:'';
    const inspired=groups.length?`<section id="inspired-results" class="inspired-results" aria-label="Inspired by your request"><div class="inspired-heading"><p class="eyebrow">${icon('sparkles')}SMART SUGGESTIONS</p><h2 tabindex="-1">Inspired by your request</h2></div>${groups.map(info=>suggestionGroup(r,info)).join('')}</section>`:'';
    const empty=`<div class="empty"><p>No results for “${esc(query)}”${filterCount(filters)?' with these filters':''}.</p><button class="pill" data-action="search-filters">Edit search & filters</button></div>`;
    return `<h1 class="sr-only" tabindex="-1">${r.matchesExpanded?'Matches by name':'Search results'}</h1>${appliedFilters(r)}${names}${inspired}${!showNames&&!groups.length?empty:''}`;
  }
  function suggestionsPage(r){
    const list=r.trackIds.map(byId),info=sourceInfo(r.sourceId);
    return `<p class="eyebrow">SMART SUGGESTIONS</p><h1 class="page-title" tabindex="-1">Inspired by your request</h1><p class="page-description">“${esc(r.query)}”</p>${source(info.id)}<p class="metadata">${list.length} tracks · ${duration(list)}</p><div class="action-row"><button class="pill accent" data-action="play-suggestions" data-source="${info.id}">${icon('play')}Play all ${list.length}</button><button class="pill" data-action="enqueue-suggestions" data-source="${info.id}">${icon('add')}Enqueue</button></div>${trackRows(list,`suggestions:${info.id}`,false,true)}`;
  }
  function folderPage(r){return `<p class="eyebrow">FOLDER</p><h1 class="page-title" tabindex="-1">${esc(r.name||'Music folders')}</h1>${source()}${r.name?`<section class="section">${heading('TRACKS')}${trackRows(albumTracks(0))}</section>`:`<section class="section">${heading('FOLDERS')}<div class="entity-row"><button class="row-open" data-action="folder" data-name="Jazz" data-focus-key="folder-jazz">${icon('folder')}<span class="row-copy"><strong>Jazz</strong></span>${icon('right')}</button></div></section>`}`;}
  function render(restore=false){const r=current();$('#appbar').innerHTML=r.kind==='home'?`<img class="wordmark" src="../../../assets/images/kalinka_logo.svg" alt="Kalinka"><span class="bar-title"></span>${ib('search','search','Search all music')}<span class="online-dot" title="Demo connection"></span>`:`${ib('back','back',`Back to ${pageTitle(routes[Math.max(0,position-1)])}`)}<span class="bar-title">${r.kind==='search'?(r.matchesExpanded?'NAME MATCHES':'RESULTS'):`<span>Back to</span> ${esc(pageTitle(routes[Math.max(0,position-1)]))}`}</span>${ib('home','home','Home')}${r.kind==='search'?filterButton(r):ib('search','search','Search all music')}`;const views={home:homePage,source:sourcePage,catalog:catalogPage,album:albumPage,artist:artistPage,collection:collectionPage,playlist:playlistPage,suggestions:suggestionsPage,search:searchPage,folder:folderPage};$('#page').innerHTML=`<div class="page-content">${(views[r.kind]||homePage)(r)}</div>`;renderPlayer();requestAnimationFrame(()=>{scroll.scrollTop=r.scroll||0;const focus=restore&&r.focus?Array.from($('.browse-pane').querySelectorAll('[data-focus-key]')).find(el=>el.dataset.focusKey===r.focus):null;(focus||$('#page h1'))?.focus({preventScroll:true});});}
  function renderPlayer(){const t=state.queue[state.at]||tracks[0],a=albums[t.albumId];$('#player').innerHTML=`<div class="player-top"><button data-action="player-tab" data-tab="playing" aria-pressed="${state.playerTab==='playing'}">PLAYING</button><button data-action="player-tab" data-tab="queue" aria-pressed="${state.playerTab==='queue'}">QUEUE · ${state.queue.length}</button></div>${state.playerTab==='queue'?`<ol class="queue-list">${state.queue.map((x,i)=>`<li><button data-action="queue-track" data-index="${i}">${i===state.at&&state.playing?icon('play'):''}${esc(x.title)}<small>${esc(x.artist)} · ${sourceInfo(x.sourceId).name}</small></button></li>`).join('')}</ol>`:`<div class="player-art">${art(a.art)}</div><h2>${esc(t.title)}</h2><p class="player-caption">${t.artist}</p><span class="signal">${sourceInfo(a.sourceId).name.toUpperCase()} · PLAYBACK SIMULATION</span><div class="progress"></div><div class="time"><span>0:00</span><span>${time(t.seconds)}</span></div><div class="transport">${ib('previous','previous','Previous track')}<button class="icon-button primary-play" data-action="toggle-play" aria-label="${state.playing?'Pause':'Play'}">${icon(state.playing?'pause':'play')}</button>${ib('next','next','Next track')}</div>`}`;$('#miniplayer').innerHTML=`<div class="mini-art">${art(a.art)}</div><div class="mini-copy"><strong>${esc(t.title)}</strong><small>${esc(t.artist)} · ${sourceInfo(t.sourceId).name}</small></div>${ib('show-queue','add','Show queue')}<button class="icon-button primary-play" data-action="toggle-play" aria-label="${state.playing?'Pause':'Play'}">${icon(state.playing?'pause':'play')}</button>`;}
  function suggestionContext(sourceId){return current().kind==='suggestions'?current().trackIds.map(byId):suggestionsFor(current(),sourceId);}
  function playback(list,start=0){state.queue=[...list];state.at=start;state.playing=true;renderPlayer();refreshCurrentRows();toast(`Playing ${list[start].title}`);}
  function refreshCurrentRows(){document.querySelectorAll('.track-row').forEach(row=>row.classList.toggle('current',state.playing&&row.querySelector('[data-id]')?.dataset.id===state.queue[state.at]?.id));}
  function enqueue(list,next=false){state.queue.splice(next?state.at+1:state.queue.length,0,...list);renderPlayer();toast(`${list.length===1?list[0].title:`${list.length} tracks`} ${next?'will play next':'added to queue'}`);}
  function menuChoice(action,label,symbol,attrs=''){return `<button class="menu-choice" data-action="${action}" ${attrs}>${icon(symbol)}<span>${esc(label)}</span></button>`;}
  function tab(id){stash();current().tab=id;current().scroll=0;render();requestAnimationFrame(()=>$('#page [role=tab][aria-selected=true]')?.focus({preventScroll:true}));}
  document.addEventListener('keydown',e=>{if(e.target.getAttribute('role')==='tab'&&['ArrowLeft','ArrowRight','Home','End'].includes(e.key)){e.preventDefault();const buttons=[...e.target.parentElement.querySelectorAll('[role=tab]')];let n=buttons.indexOf(e.target);n=e.key==='Home'?0:e.key==='End'?buttons.length-1:(n+(e.key==='ArrowRight'?1:-1)+buttons.length)%buttons.length;tab(buttons[n].dataset.tab);}});
  document.addEventListener('submit',e=>{
    if(!e.target.matches('[data-search],#search-filter-form'))return;
    e.preventDefault();const query=String(new FormData(e.target).get('query')||'').trim();if(!query)return;
    if(e.target.id==='search-filter-form'){
      const filters=cleanFilters(filterDraft);
      closeDialog(()=>{
        rememberFilters(filters);
        if(current().kind==='search'&&current().query===query){current().matchesExpanded=false;updateSearchFilters(filters);}
        else open({kind:'search',query,filters});
      });
    }else open({kind:'search',query});
  });
  document.addEventListener('click',e=>{
    const el=e.target.closest('[data-action]');if(!el)return;const d=el.dataset;const id=Number(d.id||0);const list=albumTracks(id);
    switch(d.action){
      case 'home':goHome();break;case 'back':back();break;
      case 'source':open({kind:'source',provider:d.provider||'My Library'});break;
      case 'catalog':open({kind:'catalog',category:d.category||'Recently added',provider:d.provider||'My Library'});break;
      case 'album':open({kind:'album',id});break;case 'artist':open({kind:'artist',id,tab:'albums'});break;
      case 'collection':open({kind:'collection'});break;
      case 'playlist':open({kind:'playlist'});break;case 'folder':open({kind:'folder',name:d.name});break;
      case 'search':showSearchFilters();break;
      case 'search-filters':showSearchFilters();break;
      case 'draft-filter':{
        if(d.facet==='kind')filterDraft.kind=d.value;
        else filterDraft[d.facet]=filterDraft[d.facet].includes(d.value)?filterDraft[d.facet].filter(v=>v!==d.value):[...filterDraft[d.facet],d.value];
        $('#filter-choices').innerHTML=filterChoices();
        $('#filter-choices').querySelector(`[data-facet="${d.facet}"][data-value="${d.value}"]`)?.focus({preventScroll:true});positionDialog();break;
      }
      case 'reset-draft-filters':filterDraft=cleanFilters();$('#filter-choices').innerHTML=filterChoices();positionDialog();break;
      case 'remove-search-filter':{const f=filtersFor(current());if(d.facet==='kind')f.kind='all';else f[d.facet]=f[d.facet].filter(v=>v!==d.value);updateSearchFilters(f);break;}
      case 'reset-search-filters':current().matchSource=null;updateSearchFilters(cleanFilters());break;
      case 'match-source':stash();current().matchSource=d.source||null;render(true);break;
      case 'tab':tab(d.tab);break;
      case 'all-matches':open({...current(),matchesExpanded:true,scroll:0,focus:undefined});break;
      case 'all-suggestions':open({kind:'suggestions',query:current().query,sourceId:d.source,trackIds:suggestionsFor(current(),d.source).map(t=>t.id)});break;
      case 'play-suggestions':playback(suggestionContext(d.source));break;
      case 'enqueue-suggestions':enqueue(suggestionContext(d.source));break;
      case 'play-playlist':playback(providerPlaylistTracks());break;
      case 'enqueue-playlist':enqueue(providerPlaylistTracks());break;
      case 'play-album':playback(list);break;case 'enqueue-album':enqueue(list);break;
      case 'play-collection':playback(collectionTracks());break;case 'enqueue-collection':enqueue(collectionTracks());break;
      case 'play-track':{const t=byId(d.id);const context=d.context?.startsWith('album:')?albumTracks(t.albumId):d.context==='collection'?collectionTracks():d.context==='playlist'?providerPlaylistTracks():d.context?.startsWith('suggestions:')?suggestionContext(d.context.split(':')[1]):[t];playback(context,context.findIndex(x=>x.id===t.id));break;}
      case 'toggle-play':state.playing=!state.playing;renderPlayer();refreshCurrentRows();break;
      case 'next':case 'previous':state.at=(state.at+(d.action==='next'?1:-1)+state.queue.length)%state.queue.length;renderPlayer();refreshCurrentRows();break;
      case 'player-tab':state.playerTab=d.tab;renderPlayer();break;
      case 'show-queue':showDialog('Queue',state.queue.map((t,i)=>menuChoice('queue-track',t.title,'play',`data-index="${i}"`)).join(''));break;
      case 'queue-track':{const play=()=>{state.at=Number(d.index);state.playing=true;renderPlayer();refreshCurrentRows();};if($('#action-dialog').open)closeDialog(play);else play();break;}
      case 'track-menu':{const t=byId(d.id);showDialog(t.title,menuChoice('menu-next','Play next','next',`data-track="${t.id}"`)+menuChoice('menu-enqueue','Enqueue','add',`data-track="${t.id}"`)+menuChoice('menu-album','Open album','album',`data-id="${t.albumId}"`)+menuChoice('menu-artist','Open artist','person',`data-id="${t.artistId}"`));break;}
      case 'album-menu':showDialog(albums[id].title,menuChoice('menu-next','Play next','next',`data-album="${id}"`)+menuChoice('menu-enqueue','Enqueue','add',`data-album="${id}"`)+menuChoice('menu-artist','Open artist','person',`data-id="${albums[id].artistId}"`));break;
      case 'collection-menu':showDialog(collection.title,menuChoice('menu-next','Play next','next','data-collection="true"')+menuChoice('menu-enqueue','Enqueue','add','data-collection="true"')+menuChoice('rename','Rename collection','edit'));break;
      case 'rename':closeDialog(()=>showDialog('Rename collection',`<p class="dialog-text">Changes here affect only this prototype.</p><label for="collection-name">Collection name</label><input class="rename-input" id="collection-name" value="${esc(collection.title)}"><button class="pill accent" data-action="save-name">Save</button>`));break;
      case 'save-name':{const name=$('#collection-name').value.trim();if(name)closeDialog(()=>{collection.title=name;stash();render(true);toast('Collection renamed');});break;}
      case 'menu-next':case 'menu-enqueue':{const items=d.track?[byId(d.track)]:d.collection?collectionTracks():albumTracks(d.album);closeDialog(()=>enqueue(items,d.action==='menu-next'));break;}
      case 'menu-album':closeDialog(()=>open({kind:'album',id}));break;
      case 'menu-artist':closeDialog(()=>open({kind:'artist',id,tab:'albums'}));break;
      case 'filter':showDialog('Genre',`<p class="dialog-text">Example source-declared choices for this catalog.</p>${['All genres','Jazz','Ambient','Electronic','Classical'].map(g=>`<button class="menu-choice${(current().genre||'All genres')===g?' selected':''}" data-action="choose-genre" data-genre="${g}">${icon((current().genre||'All genres')===g?'check':'music')}${g}</button>`).join('')}`);break;
      case 'choose-genre':closeDialog(()=>{current().genre=d.genre;current().scroll=0;render();});break;
      case 'reset-filter':current().genre='All genres';current().scroll=0;render();break;
      case 'pin':state.pinned=!state.pinned;stash();render(true);toast(state.pinned?'Pinned to Home in this demo':'Removed from Home in this demo');break;
      case 'close-dialog':closeDialog();break;
    }
  });
  document.querySelectorAll('[data-mode]').forEach(button=>button.addEventListener('click',()=>{const top=scroll.scrollTop;$('#prototype').classList.toggle('phone',button.dataset.mode==='phone');document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));requestAnimationFrame(()=>scroll.scrollTop=top);}));
  $('#large-text').addEventListener('click',e=>{const active=$('#prototype').classList.toggle('large-text');e.currentTarget.setAttribute('aria-pressed',String(active));});
  $('#jump').addEventListener('change',e=>{const kind=e.target.value;if(!kind)return;if(kind==='home')goHome();else open({kind,id:0,tab:kind==='search'?'all':'albums',query:'Mara Vale'});e.target.value='';});
  render();
  if(window.innerWidth<900){$('#prototype').classList.add('phone');document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.mode==='phone')));}
  const parameters=new URLSearchParams(location.search);
  const initial=parameters.get('screen')||'album';
  if(['album','artist','playlist','collection','source','catalog','search'].includes(initial))open({kind:initial,id:0,tab:initial==='search'?'all':'albums',query:parameters.get('query')||'Mara Vale'});
})();
