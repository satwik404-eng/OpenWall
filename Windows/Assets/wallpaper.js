'use strict';
const canvas=document.querySelector('canvas'),video=document.querySelector('video');
let item={id:'aurora'},paused=true,speed=1,frame=0,phase=1.7,last=0,nextDraw=0,motionFPS=60;
function draw(){MotionRenderer.draw(canvas,item.id,phase);}
function animate(now){
 frame=0;if(paused||item.filename)return;
 if(!last)last=now;
 phase+=(now-last)*speed/8000;last=now;
 const interval=1000/motionFPS;
 if(!nextDraw||now>=nextDraw-.5){draw();nextDraw=(nextDraw||now)+interval;if(nextDraw<now)nextDraw=now+interval;}
 frame=requestAnimationFrame(animate);
}
function resize(){const scale=Math.min(devicePixelRatio||1,1.5);canvas.width=Math.ceil(innerWidth*scale);canvas.height=Math.ceil(innerHeight*scale);if(!item.filename)draw();}
window.initializeWallpaper=function(config){
 item=config;paused=!!config.paused;speed=config.speed||1;motionFPS=[24,60,120].includes(config.motionFPS)?config.motionFPS:60;resize();
 if(item.filename){canvas.hidden=true;video.style.display='block';video.src='https://'+(config.qualityCopy?'quality':'media')+'.openwall.local/'+encodeURIComponent(item.filename);video.onerror=()=>window.chrome?.webview?.postMessage({error:'video'});video.onloadeddata=()=>window.chrome?.webview?.postMessage({loaded:true});}
 window.setPlayback(paused,speed,motionFPS);
};
window.setPlayback=function(value,rate,fps=60){
 paused=value;speed=rate;motionFPS=[24,60,120].includes(fps)?fps:60;cancelAnimationFrame(frame);frame=0;last=0;nextDraw=0;
 if(item.filename){video.playbackRate=speed;if(paused)video.pause();else video.play().catch(()=>window.chrome?.webview?.postMessage({error:'video'}));}
 else if(!paused)frame=requestAnimationFrame(animate);else draw();
};
window.addEventListener('resize',resize);
