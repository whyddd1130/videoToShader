#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float u_Angle;
uniform float u_Strength;
uniform vec2 u_ScreenParams;
uniform float u_DownSample;
uniform float u_gamma;
float normpdf(in float x, in float sigma)
{
	return exp(-0.5*x*x/(sigma*sigma));
}

vec4 gaussianBlur(sampler2D i_InputTex, vec2 i_Uv, vec2 i_Dir, float i_Strength)
{
    float sigma = 4.0;
    float first = normpdf(0.0, sigma);
    float weight = 0.5 * 1.02 + 0.5;
    weight = first;
    vec4 sum            = vec4(0.0);
    vec4 result         = vec4(0.0);
    vec2 unit_uv        = i_Dir * u_DownSample;
    vec4 curColor       = texture2D(i_InputTex, i_Uv);
    float gamma = u_gamma; 
    vec4 center = pow(curColor, vec4(gamma)) * weight;
    vec4 sum_weight = vec4(weight);
    float s = i_Strength;
    for(int i=1;i<=1000;++i)
    {
        if (float(i) > i_Strength) break;
        float curIndex = float(i);
        vec2 curRightCoordinate = i_Uv+float(i)*unit_uv;
        vec2 curLeftCoordinate  = i_Uv+float(-i)*unit_uv;
        vec4 rightColor = texture2D(i_InputTex, curRightCoordinate);
        vec4 leftColor = texture2D(i_InputTex, curLeftCoordinate);
        rightColor = pow(rightColor, vec4(gamma));
        leftColor = pow(leftColor, vec4(gamma));
        weight = normpdf(curIndex / s * 16.0, sigma);
        sum += (rightColor + leftColor) * weight;
        sum_weight.a += weight * 2.0;
    }
    result = (sum + center) / sum_weight.a;
    return pow(result, vec4(1.0 / gamma));
}

void main()
{
    float theta = u_Angle / 180.0 * 3.1415926;
    vec2 ratio = 720.0 * u_ScreenParams.xy / min(u_ScreenParams.x, u_ScreenParams.y);
    vec2 dir = vec2(cos(theta), sin(theta)) / ratio.xy;
    vec4 color = gaussianBlur(inputImageTexture, textureCoord, dir, u_Strength);
    gl_FragColor = color;
}
