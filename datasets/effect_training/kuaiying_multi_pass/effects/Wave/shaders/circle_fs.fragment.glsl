#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 u_ScreenParams;
uniform vec2 u_center;
uniform float u_maxDistance;
uniform float u_smoothDistance;
uniform float u_circleWidth;
uniform float u_circleDisWidthChange;
uniform float u_circleDisSmoothChange;
uniform float u_nowRadius;
uniform float u_nowRadius1;
uniform float u_mask;

float normpdf(in float x, in float sigma)
{
    return 0.39894*exp(-0.5*x*x/(sigma*sigma))/sigma;
}
vec4 enCode(float a)
{
    float a1 = floor(a*255.);
    float b1 = fract(a*255.);
    float a2 = floor(b1*255.);
    float b2 = fract(b1*255.);
    float a3 = floor(b2*255.);
    float b3 = fract(b2*255.);
    return vec4(a1/255.,a2/255.,a3/255.,b3);
}
void main()
{
    vec2 ratio = u_ScreenParams.xy / min(u_ScreenParams.x, u_ScreenParams.y);
    vec2 uv0 = textureCoord - u_center;
    uv0 *= ratio;
    float nowLen = length(uv0);
    float nowRadius = u_nowRadius;
    float nowWidth = u_circleWidth*(1.+(nowRadius)/(2.*u_maxDistance)*u_circleDisWidthChange);
    float nowSmoothDistance = max(0.,u_smoothDistance*(2.-(nowRadius)/(2.*u_maxDistance)*u_circleDisSmoothChange));
    float mask = smoothstep(nowRadius-nowSmoothDistance, nowRadius, nowLen) * (1.-smoothstep(nowRadius+nowWidth, nowRadius+nowWidth+nowSmoothDistance, nowLen));
    
    nowRadius = u_nowRadius1;
    nowWidth = u_circleWidth*(1.+(nowRadius)/(2.*u_maxDistance)*u_circleDisWidthChange);
    nowSmoothDistance = max(0.,u_smoothDistance*(2.-(nowRadius)/(2.*u_maxDistance)*u_circleDisSmoothChange));
    mask += smoothstep(nowRadius-nowSmoothDistance, nowRadius, nowLen) * (1.-smoothstep(nowRadius+nowWidth, nowRadius+nowWidth+nowSmoothDistance, nowLen));
    mask *= min(smoothstep(0., u_maxDistance, nowLen)+0.5,1.0);
    gl_FragColor = vec4(enCode(mask*u_mask));
}
