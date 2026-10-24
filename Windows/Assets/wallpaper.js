'use strict';
const canvas=document.querySelector('canvas'),video=document.querySelector('video');
let item={id:'aurora'},paused=true,speed=1,frame=0,phase=1.7,last=0,lastDraw=0;
function draw(){MotionRenderer.draw(canvas,item.id,phase);}
function animate(now){frame=0;if(paused||item.filename)return;if(!last)last=now;phase+=(now-last)*speed/8000;last=now;if(now-lastDraw>=1000/24){draw();lastDraw=now;}frame=requestAnimationFrame(animate);}
function resize(){const scale=Math.min(devicePixelRatio||1,1.5);canvas.width=Math.ceil(innerWidth*scale);canvas.height=Math.ceil(innerHeight*scale);if(!item.filename)draw();}
window.initializeWallpaper=function(config){item=config;paused=!!config.paused;speed=config.speed||1;resize();if(item.filename){canvas.hidden=true;video.style.display='block';video.src='https://media.openwall.local/'+encodeURIComponent(item.filename);video.onerror=()=>window.chrome?.webview?.postMessage({error:'video'});video.onloadeddata=()=>window.chrome?.webview?.postMessage({loaded:true});}setPlayback(paused,speed);};
window.setPlayback=function(value,rate){paused=value;speed=rate;cancelAnimationFrame(frame);frame=0;last=0;if(item.filename){video.playbackRate=speed;if(paused)video.pause();else video.play().catch(()=>window.chrome?.webview?.postMessage({error:'video'}));}else if(!paused)frame=requestAnimationFrame(animate);else draw();};
window.addEventListener('resize',resize);
