'use strict';
window.MotionRenderer = (() => {
  const catalog = window.OpenWallCatalog;
  const items = new Map(catalog.items.map(item => [item.id, item]));
  function vertices(shape, time) {
    const t = time * shape.rate + shape.phase;
    const angle = shape.rotation + Math.sin(t) * shape.rotate;
    const scale = 1 + Math.sin(t) * shape.pulse;
    const dx = Math.sin(t) * shape.driftX, dy = Math.cos(t) * shape.driftY;
    const co = Math.cos(angle), si = Math.sin(angle);
    return shape.points.map(p => {
      const warp = p[2] || 0;
      const x = p[0] + Math.cos(p[1] * shape.frequency + t) * shape.warpX * warp;
      const y = p[1] + Math.sin(p[0] * shape.frequency + t) * shape.warpY * warp;
      const a = (x - shape.pivot[0]) * scale, b = (y - shape.pivot[1]) * scale;
      return [shape.pivot[0] + a * co - b * si + dx, shape.pivot[1] + a * si + b * co + dy];
    });
  }
  function gradientMotion(shape,time) {
    const t=time*shape.rate+shape.phase,angle=shape.rotation+Math.sin(t)*shape.rotate;
    const scale=1+Math.sin(t)*shape.pulse;
    const a=(shape.fill.start[0]-shape.pivot[0])*scale,b=(shape.fill.start[1]-shape.pivot[1])*scale;
    return {center:[shape.pivot[0]+a*Math.cos(angle)-b*Math.sin(angle)+Math.sin(t)*shape.driftX,
                   shape.pivot[1]+a*Math.sin(angle)+b*Math.cos(angle)+Math.cos(t)*shape.driftY],scale};
  }
  function shading(ctx, fill, palette, w, h, motion={center:fill.start,scale:1}) {
    const color = stop => { const c = stop.color < 0 ? [1,1,1] : palette[stop.color]; return `rgba(${c.map(n => n*255).join(',')},${stop.alpha})`; };
    if (fill.kind === 'solid') return color(fill.stops[0]);
    const gradient = fill.kind === 'radial'
      ? ctx.createRadialGradient(motion.center[0]*w,motion.center[1]*h,0,motion.center[0]*w,motion.center[1]*h,fill.end[1]*Math.min(w,h)*motion.scale)
      : ctx.createLinearGradient(fill.start[0]*w,fill.start[1]*h,fill.end[0]*w,fill.end[1]*h);
    for (const stop of fill.stops) gradient.addColorStop(stop.location,color(stop));
    return gradient;
  }
  function draw(canvas, id, time = 1.7) {
    const item = items.get(id) || catalog.items[0], ctx = canvas.getContext('2d');
    const w = canvas.width, h = canvas.height;
    ctx.globalAlpha=1; ctx.clearRect(0,0,w,h); ctx.fillStyle='#000'; ctx.fillRect(0,0,w,h);
    ctx.fillStyle=shading(ctx,catalog.background,item.palette,w,h);ctx.fillRect(0,0,w,h);
    for (const shape of catalog.scenes[item.style]) {
      const points = vertices(shape,time); if (!points.length) continue;
      ctx.globalAlpha=1-shape.opacityPulse*(.5+.5*Math.sin(time*shape.opacityRate+shape.opacityPhase));
      ctx.beginPath();
      if (shape.pixelRadius > 0) ctx.ellipse(points[0][0]*w+shape.pixelRadius,points[0][1]*h+shape.pixelRadius,shape.pixelRadius,shape.pixelRadius,0,0,Math.PI*2);
      else {
        ctx.moveTo(points[0][0]*w,points[0][1]*h);
        for(let i=1;i<points.length;i++)ctx.lineTo(points[i][0]*w,points[i][1]*h);
        if(shape.closed)ctx.closePath();
      }
      const shader = shading(ctx,shape.fill,item.palette,w,h,gradientMotion(shape,time));
      if(shape.stroke>0){ctx.strokeStyle=shader;ctx.lineWidth=shape.stroke*Math.min(w,h);ctx.stroke();}
      else{ctx.fillStyle=shader;ctx.fill();}
    }
    ctx.globalAlpha=1;
  }
  return {draw,vertices,gradientMotion,items};
})();
