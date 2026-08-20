precision highp float;


uniform float uProgress;
uniform float uTime;
uniform sampler2D inputImageTexture;
#define iTime uTime
#define rIns (0.3 + 2.0 * uProgress)
#define gIns (0.3 + 2.0 * uProgress)
#define bIns (0.3 + 2.0 * uProgress)
varying vec2 uv;
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
// vec4 hash24(vec2 p){
//     vec4 p4 = fract(p.xyxy*34.5);
//     p4+=dot(p4,p4.wyzx+(15.44));
//     return fract((p4+p4.wyzx)*p4.yzxw);
// }
vec3 hash23(vec2 p){
    vec3 p3 = fract(p.xyx*33.5);
    p3+=dot(p3,p3.yzx+(12.1+iTime));
    return fract((p3.xyz+p3.yzx)*p3.zyx);
}
vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
vec3 blendColor(vec3 base, vec3 blend) {
    float topgray = dot(blend.rgb,vec3(0.299,0.587, 0.114));
    float bottomgray = dot(base.rgb,vec3(0.299,0.587, 0.114));
    vec3 resultCol = blend.rgb - topgray+bottomgray;
    //  if(resultCol.r>1.||resultCol.g>1.||resultCol.b>1.){
    //         resultCol = vec3(1.)*(bottomgray-topgray)/(1.-topgray)+blend.rgb;
    //     }
    return resultCol;
}
float blendDarken(float base, float blend) {
    return min(blend,base);
}

vec3 blendDarken(vec3 base, vec3 blend) {
    return vec3(blendDarken(base.r,blend.r),blendDarken(base.g,blend.g),blendDarken(base.b,blend.b));
}
void main()
{
    float scale = 2.0;
    // vec3 oriCol = texture2D(inputImageTexture,uv).rgb;
    // float gray = dot(oriCol.rgb,vec3(0.299 ,0.587,0.114));
    // vec2 noiseUV = floor(uv*(u_ScreenParams.xy)/scale)/u_ScreenParams.xy*scale;
    vec2 noiseUV = uv;
    vec3 firstNoise  = hash23(noiseUV);
    vec3 resultNoise = firstNoise;
    resultNoise=(resultNoise-vec3(0.5))*vec3(rIns,gIns,bIns)+vec3(0.5);
    gl_FragColor = vec4(firstNoise,1.0);
}
