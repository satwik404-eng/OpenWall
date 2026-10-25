const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const script=fs.readFileSync(require('node:path').join(__dirname,'../Windows/Assets/wallpaper.js'),'utf8');
function harness(){
 let queued=new Map(),key=0,draws=[];
 const canvas={width:0,height:0},video={style:{},pause(){},play(){return Promise.resolve()}};
 const context=vm.createContext({window:{addEventListener(){}},document:{querySelector:s=>s==='canvas'?canvas:video},innerWidth:1920,innerHeight:1080,devicePixelRatio:1,MotionRenderer:{draw(c,id,phase){draws.push(phase)}},requestAnimationFrame:fn=>{queued.set(++key,fn);return key},cancelAnimationFrame:id=>queued.delete(id)});
 vm.runInContext(script,context);
 return {context,video,draws,queued,tick(now){const callbacks=[...queued.values()];queued.clear();callbacks.forEach(fn=>fn(now));}};
}
for(const refresh of [60,120,240])for(const fps of [24,60,120]){
 const h=harness();h.context.window.initializeWallpaper({id:'dunes-teal',paused:false,speed:1,motionFPS:fps});h.draws.length=0;
 for(let i=0;i<refresh*2;i++)h.tick(100+i*1000/refresh);
 const expected=Math.min(refresh,fps)*2;
 assert.ok(Math.abs(h.draws.length-expected)<=2,`${fps} fps on ${refresh} Hz: ${h.draws.length}`);
 const phase=vm.runInContext('phase',h.context);
 assert.ok(Math.abs(phase-(1.7+(2-1/refresh)/8))<.001,'frame rate must not change motion speed');
 h.context.window.setPlayback(true,1,fps);assert.equal(h.queued.size,0,'pause stops frame callbacks');
 h.context.window.setPlayback(false,1,120);assert.equal(h.queued.size,1,'resume has exactly one animation loop');
 assert.equal(vm.runInContext('phase',h.context),phase,'switching frame rate retains motion phase');
 console.log(`PASS ${fps} fps at ${refresh} Hz: ${h.draws.length} frames/2 seconds; same flow, pause and resume`);
}
const h=harness();h.context.window.initializeWallpaper({id:'video',filename:'fixture-1080.mp4',qualityCopy:true,paused:true,speed:1,motionFPS:120});assert.equal(h.video.src,'https://quality.openwall.local/fixture-1080.mp4');assert.equal(h.queued.size,0);
h.context.window.initializeWallpaper({id:'video',filename:'original.mp4',paused:true,speed:1});assert.equal(h.video.src,'https://media.openwall.local/original.mp4');
console.log('PASS video quality copies and originals use their correct local media hosts');
