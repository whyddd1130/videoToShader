#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform sampler2D sdfImageTexture;

uniform vec2 u_ScreenParams;
uniform float waterIns;
uniform float stepIns;

float deCode(vec4 a){
    return a.x+a.y/255.+a.z/(255.*255.)+a.w/(255.*255.*255.);
}
float mirror(float x){
    return abs(mod(x-1.0,2.0)-1.0);
}
vec2 mirror(vec2 uv){
    return vec2(mirror(uv.x),mirror(uv.y));
}
vec4 getCol(vec2 uv){
    vec2 mySize = u_ScreenParams.xy/min(u_ScreenParams.x,u_ScreenParams.y)*720.;
    vec2 offset = vec2(1. * stepIns)/(mySize);

    float gray1 = deCode(texture2D(sdfImageTexture,uv+vec2(1,0)*offset));
    float gray11 = deCode(texture2D(sdfImageTexture,uv-vec2(1,0)*offset));
    float gray2 = deCode(texture2D(sdfImageTexture,uv+vec2(0,1)*offset));
    float gray22 = deCode(texture2D(sdfImageTexture,uv-vec2(0,1)*offset));

    vec2 grad=vec2(gray11-gray1,gray22-gray2)*10.*waterIns*deCode(texture2D(sdfImageTexture,uv));
    vec2 lastUV = mirror(uv+grad);
    vec4 resultCol = texture2D(inputImageTexture,lastUV);
    return resultCol;
}
void main()
{
    vec2 mySize = u_ScreenParams.xy / min(u_ScreenParams.x, u_ScreenParams.y) * 720.;
    vec2 offset = vec2(1.)/(mySize);
    vec4 resultCol = getCol(textureCoord) + getCol(textureCoord + offset*vec2(0.5,0))+getCol(textureCoord + offset*vec2(0,0.5))+getCol(textureCoord + offset*vec2(0.5,0.5));
    resultCol /= 4.;
    gl_FragColor = vec4(resultCol);
}
