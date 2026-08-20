precision highp float;

uniform float uProgress;
uniform float uTime;
varying highp vec2 uv0;
uniform sampler2D inputImageTexture;
#define u_Strength (20.0 + 180.0 * uProgress)
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
#define centerX 540.0
#define centerY 540.0
float uvProtect(vec2 uv)
{
    return step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
}
float mirror(float x){
    return abs(mod(x-1.0,2.0)-1.0);
}
vec2 mirror(vec2 uv){
    return vec2(mirror(uv.x),mirror(uv.y));
}
void main()
{

    vec2 uv = (uv0-0.5)*1.1+0.5;
    vec2 ratio = (u_ScreenParams.xy / max(u_ScreenParams.x, u_ScreenParams.y));
    vec2 center = vec2(centerX/1080.,centerY/1920.);
    for (int i = 1; i < 16; ++i)
    {
        uv -= center;
        uv *= ratio;
        float d = length(uv * 2.0);
        uv = uv * pow((d*d) + 1.0, -pow(u_Strength * 0.0059375, 3.0));
        uv /= ratio;

        uv += center;
    }
    gl_FragColor = texture2D(inputImageTexture, mirror(uv)) ;
}