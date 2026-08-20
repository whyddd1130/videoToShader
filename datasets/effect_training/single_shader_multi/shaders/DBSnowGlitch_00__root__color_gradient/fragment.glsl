precision highp float;

uniform float uProgress;
uniform float uTime;
#define GLSLIFY 1
varying vec2 uv0;

uniform sampler2D inputImageTexture;
#define texture inputImageTexture
#define baseTexWidth 1080.0
#define baseTexHeight 1080.0
#define timer uTime
#define interval 0.12
#define shakeIntensity (0.02 + 0.45 * uProgress)
#define xnoiseIntensity (0.02 + 0.85 * uProgress)
#define blockIntensity (0.02 + 0.90 * uProgress)
#define rgbIntensity (0.02 + 0.70 * uProgress)
#define whiteIntensity (0.00 + 0.60 * uProgress)
#define light (0.00 + 0.70 * uProgress)
// uniform sampler2D texture;

// varying highp vec2 uv0;

//#pragma glslify: random = require(glsl-util/random);
//#pragma glslify: snoise3 = require(glsl-noise/simplex/3d)

mediump float random(vec2 c){
  return fract(sin(dot(c.xy,vec2(12.9898,78.233)))*43758.5453);
}

mediump vec3 mod289(vec3 x){
  // return x-floor(x*(1./289.))*289.;
  return mod(x,289.);
}

mediump vec4 mod289(vec4 x){
  // return x-floor(x*(1./289.))*289.;
  return mod(x,289.);
}

mediump vec4 permute(vec4 x){
  return mod289(((x*34.)+1.)*x);
}

vec4 taylorInvSqrt(vec4 r)
{
  return 1.79284291400159-.85373472095314*r;
}

float snoise3(vec3 v)
{
  const vec2 C=vec2(1./6.,1./3.);
  const vec4 D=vec4(0.,.5,1.,2.);
  
  // First corner
  vec3 i=floor(v+dot(v,C.yyy));
  vec3 x0=v-i+dot(i,C.xxx);
  
  // Other corners
  mediump vec3 g=step(x0.yzx,x0.xyz);
  mediump vec3 l=1.-g;
  mediump vec3 i1=min(g.xyz,l.zxy);
  mediump vec3 i2=max(g.xyz,l.zxy);
  
  //   x0 = x0 - 0.0 + 0.0 * C.xxx;
  //   x1 = x0 - i1  + 1.0 * C.xxx;
  //   x2 = x0 - i2  + 2.0 * C.xxx;
  //   x3 = x0 - 1.0 + 3.0 * C.xxx;
  vec3 x1=x0-i1+C.xxx;
  vec3 x2=x0-i2+C.yyy;// 2.0*C.x = 1/3 = C.y
  vec3 x3=x0-D.yyy;// -1.0+3.0*C.x = -0.5 = -D.y
  
  // Permutations
  i=mod289(i);
  mediump vec4 p=permute(permute(permute(i.z+vec4(0.,i1.z,i2.z,1.))+i.y+vec4(0.,i1.y,i2.y,1.))+i.x+vec4(0.,i1.x,i2.x,1.));
  
  // Gradients: 7x7 points over a square, mapped onto an octahedron.
  // The ring size 17*17 = 289 is close to a multiple of 49 (49*6 = 294)
  mediump float n_=.142857142857;// 1.0/7.0
  mediump vec3 ns=n_*D.wyz-D.xzx;
  
  mediump vec4 j=p-49.*floor(p*ns.z*ns.z);//  mod(p,7*7)
  
  mediump vec4 x_=floor(j*ns.z);
  mediump vec4 y_=floor(j-7.*x_);// mod(j,N)
  
  mediump vec4 x=x_*ns.x+ns.yyyy;
  mediump vec4 y=y_*ns.x+ns.yyyy;
  mediump vec4 h=1.-abs(x)-abs(y);
  
  mediump vec4 b0=vec4(x.xy,y.xy);
  mediump vec4 b1=vec4(x.zw,y.zw);
  
  //vec4 s0 = vec4(lessThan(b0,0.0))*2.0 - 1.0;
  //vec4 s1 = vec4(lessThan(b1,0.0))*2.0 - 1.0;
  mediump vec4 s0=floor(b0)*2.+1.;
  mediump vec4 s1=floor(b1)*2.+1.;
  mediump vec4 sh=-step(h,vec4(0.));
  
  mediump vec4 a0=b0.xzyw+s0.xzyw*sh.xxyy;
  mediump vec4 a1=b1.xzyw+s1.xzyw*sh.zzww;
  
  mediump vec3 p0=vec3(a0.xy,h.x);
  mediump vec3 p1=vec3(a0.zw,h.y);
  mediump vec3 p2=vec3(a1.xy,h.z);
  mediump vec3 p3=vec3(a1.zw,h.w);
  
  //Normalise gradients
  vec4 norm=taylorInvSqrt(vec4(dot(p0,p0),dot(p1,p1),dot(p2,p2),dot(p3,p3)));
  p0*=norm.x;
  p1*=norm.y;
  p2*=norm.z;
  p3*=norm.w;
  
  // Mix final noise value
  mediump vec4 m=max(.6-vec4(dot(x0,x0),dot(x1,x1),dot(x2,x2),dot(x3,x3)),0.);
  m=m*m;
  return 42.*dot(m*m,vec4(dot(p0,x0),dot(p1,x1),dot(p2,x2),dot(p3,x3)));
}

void main(void)
{
  mediump vec2 resolution=vec2(baseTexWidth,baseTexHeight);
  mediump float time=timer;
  vec2 vUv=uv0;
  mediump float strength=smoothstep(interval*.5,interval,interval-mod(time,interval));
  mediump vec2 shake=vec2(strength*8.+.5)*vec2(random(vec2(time))*2.-1.,random(vec2(time*2.))*2.-1.)/resolution*shakeIntensity;
  
  mediump float y=vUv.y*resolution.y;
  float rgbWave=(snoise3(vec3(0.,y*.01,time*400.))*(2.+strength*32.)
  *snoise3(vec3(0.,y*.02,time*200.))*(1.+strength*4.)
  +step(.9995,sin(y*.005+time*1.6))*12.
  +step(.9999,sin(y*.005+time*2.))*-18.
)/resolution.x*xnoiseIntensity;
mediump float rgbDiff=(6.+sin(time*500.+vUv.y*40.)*(20.*strength+1.))/resolution.x*rgbIntensity;
float rgbUvX=vUv.x+rgbWave;
mediump float r=texture2D(texture,vec2(rgbUvX+rgbDiff,vUv.y)+shake).r;
mediump float g=texture2D(texture,vec2(rgbUvX,vUv.y)+shake).g;
mediump float b=texture2D(texture,vec2(rgbUvX-rgbDiff,vUv.y)+shake).b;

mediump float whiteNoise=(random(vUv+mod(time,10.))*whiteIntensity-1.)*(.15+strength*.15);

float bnTime=floor(time*20.)*200.;
mediump float noiseX=step((snoise3(vec3(0.,vUv.x*3.,bnTime))+1.)/2.,.12+strength*.1);
mediump float noiseY=step((snoise3(vec3(0.,vUv.y*3.,bnTime))+1.)/2.,.12+strength*.3);
mediump float bnMask=noiseX*noiseY;
float bnUvX=vUv.x+sin(bnTime)*.2*blockIntensity+rgbWave;
mediump float bnR=texture2D(texture,vec2(bnUvX+rgbDiff,vUv.y)).r*bnMask;
mediump float bnG=texture2D(texture,vec2(bnUvX,vUv.y)).g*bnMask;
mediump float bnB=texture2D(texture,vec2(bnUvX-rgbDiff,vUv.y)).b*bnMask;
mediump vec4 blockNoise=vec4(bnR,bnG,bnB,1.);

float bnTime2=floor(time*25.)*300.;
mediump float noiseX2=step((snoise3(vec3(0.,vUv.x*2.,bnTime2))+1.)/2.,.12+strength*.4);
mediump float noiseY2=step((snoise3(vec3(0.,vUv.y*8.,bnTime2))+1.)/2.,.12+strength*.3);
mediump float bnMask2=noiseX2*noiseY2;
mediump float bnR2=texture2D(texture,vec2(bnUvX+rgbDiff,vUv.y)).r*bnMask2;
mediump float bnG2=texture2D(texture,vec2(bnUvX,vUv.y)).g*bnMask2;
mediump float bnB2=texture2D(texture,vec2(bnUvX-rgbDiff,vUv.y)).b*bnMask2;
mediump vec4 blockNoise2=vec4(bnR2,bnG2,bnB2,1.);

mediump float waveNoise=(sin(vUv.y*resolution.y)+1.)/light*(.15+strength*.2);

gl_FragColor=vec4(r,g,b,1.)*(1.-bnMask-bnMask2)+(whiteNoise+blockNoise+blockNoise2-waveNoise);
}
