precision highp float;


uniform float uProgress;
uniform float uTime;
uniform sampler2D inputImageTexture;
varying vec2 uv;
#define inputWidth 1080
#define inputHeight 1080
#define iTime uTime
#define lightIns (0.25 + 0.45 * uProgress)
#define moveX (-0.08 + 0.16 * uProgress)
#define moveY (0.08 - 0.16 * uProgress)
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
float mirror(float x){
    return abs(mod(x-1.0,2.0)-1.0);
}
vec2 mirror(vec2 uv){
    return vec2(mirror(uv.x),mirror(uv.y));
}
void main()
{
    vec2 mySize = u_ScreenParams.xy/min(u_ScreenParams.x,u_ScreenParams.y)*720.;
    vec4 col = texture2D(inputImageTexture, mirror(uv));
    float gray = dot(col.rgb,vec3(0.299 ,0.587,0.114));
    col.a*=smoothstep(lightIns,lightIns+0.1,gray);
    gl_FragColor = vec4(smoothstep(lightIns,lightIns+0.1,gray));
}
