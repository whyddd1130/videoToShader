precision highp float;

uniform float uProgress;
uniform float uTime;
varying highp vec2 uv0;
uniform sampler2D inputImageTexture;
#define iTime uTime
#define scope (0.01 + 0.18 * uProgress)
#define speed (0.8 + 3.0 * uProgress)
#define rate (4.0 + 30.0 * uProgress)
#define twistX 1
// #define PI = 3.14159;
// 
void main()
{
 float s = 1.0 - scope * 2.0;

  float ox = uv0.x;
  float oy = uv0.y;

    ox = sin(mod(uv0.y * rate * 2.0, 2.0) * 3.14159) * scope;
    ox = (uv0.x) + ox * sin(iTime);
    if (ox < 0.0){
      ox = -ox;
    }else if(ox > 1.0){
      ox = 2.0 - ox;

  }
//  if(twistY == 1){
//    oy = sin(mod(coordnate.x * rate * 2.0 + time * speed, 2.0) * PI) * scope;
//    oy = coordnate.y * s + scope + oy;
//  }

  vec2 uv = vec2(ox, oy);

  vec4 color = texture2D(inputImageTexture, uv);

  gl_FragColor = color;
}
