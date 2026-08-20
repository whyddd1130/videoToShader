#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 u_ScreenParams;
uniform float blurSize;
uniform float angle;

float normpdf(in float x, in float sigma)
{
    return 0.39894*exp(-0.5*x*x/(sigma*sigma))/sigma;
}
vec4 gaussianBlur(sampler2D i_InputTex, vec2 i_Uv, float _a)
{
    float sigma = 4.0;
    float first = normpdf(0.0, sigma);
    float weight = 0.5 * 1.02 + 0.5;

    float radian = 3.1415926 * _a / 180.0;
    vec2 dir = vec2(cos(radian), sin(radian) * u_ScreenParams.x/u_ScreenParams.y);
    dir *= blurSize * 0.1;
    vec4 sum            = vec4(0.0);
    vec4 result         = vec4(0.0);
    vec2 unit_uv        = dir;
    vec4 curColor       = texture2D(i_InputTex, i_Uv);
    float gamma = 1.0;
    vec4 centerPixel    = pow(curColor, vec4(gamma))*weight;
    float sum_weight    = weight;
    const int GLOWSAMPLE = 25;
    float s = float(GLOWSAMPLE);
    for(int i=1;i<=GLOWSAMPLE;i+=1)
    {
        vec2 curRightCoordinate = i_Uv+float(i)*unit_uv;
        vec2 curLeftCoordinate  = i_Uv+float(-i)*unit_uv;
        vec4 rightColor = texture2D(i_InputTex, curRightCoordinate);
        vec4 leftColor = texture2D(i_InputTex, curLeftCoordinate);
        weight = (normpdf(float(i) / s * 15.0, sigma) / first - 0.5) * 1.02 + 0.5;
        sum+=pow(rightColor, vec4(gamma))*weight;
        sum+=pow(leftColor, vec4(gamma))*weight;
        sum_weight+=weight*2.0;
    }
    result = (sum+centerPixel)/sum_weight; 
    return pow(clamp(result, 0.0, 1.0), vec4(1.0 / gamma));
}

void main()
{
    vec2 screenSize = u_ScreenParams;
    vec2 uv1 = textureCoord;
    vec4 res = gaussianBlur(inputImageTexture, uv1, angle);
    gl_FragColor = res;
}
