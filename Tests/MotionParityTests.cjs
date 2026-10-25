// Pure geometry comparison; the native test writes its evaluated vertices first.
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),context=vm.createContext({window:{}});
vm.runInContext(fs.readFileSync(path.join(root,'Shared/motion-catalog.js'),'utf8'),context);
vm.runInContext(fs.readFileSync(path.join(root,'Windows/Assets/motion-renderer.js'),'utf8'),context);
const catalog=context.window.OpenWallCatalog,renderer=context.window.MotionRenderer;
const native=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const gradients=JSON.parse(fs.readFileSync(path.join(path.dirname(process.argv[2]),'gradients.json'),'utf8'));
let maxError=0,count=0;
for(const [style,shapes] of Object.entries(catalog.scenes))for(let s=0;s<shapes.length;s++){
 const actual=renderer.vertices(shapes[s],1.7),expected=native[style][s];
 const gradient=renderer.gradientMotion(shapes[s],1.7);
 const opacity=1-shapes[s].opacityPulse*(.5+.5*Math.sin(1.7*shapes[s].opacityRate+shapes[s].opacityPhase));
 for(const [i,value] of [...gradient.center,gradient.scale,opacity].entries())assert.ok(Math.abs(value-gradients[style][s][i])<1e-12);
 assert.equal(actual.length,expected.length);
 for(let i=0;i<actual.length;i++)for(let c=0;c<2;c++){
  const error=Math.abs(actual[i][c]-expected[i][c]);maxError=Math.max(maxError,error);count++;
  assert.ok(error<1e-12,`${style} shape ${s} vertex ${i}: ${error}`);
 }
}
assert.equal(catalog.items.length,89);
console.log(`PASS Mac/Windows vector parity: ${count} coordinates across all 11 scenes; maximum error ${maxError}`);
console.log('PASS matching moving gradient centers, radii and star opacity on Mac/Windows');
